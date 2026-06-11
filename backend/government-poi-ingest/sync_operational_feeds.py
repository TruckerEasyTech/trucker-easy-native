#!/usr/bin/env python3
"""
Sync state/federal operational feeds (TPIMS, OHGO) into poi_operational_status.

Weigh station OPEN/CLOSED is not available from a single US government API.
Trucker Path / DAT use crowdsource; we combine:
  1) State TPIMS / OHGO official parking + site_open when configured
  2) Crowd weigh_station_reports (via app + ops-feed)
  3) NTAD static locations (ingest_ntad.py)

Usage:
  python sync_operational_feeds.py --dry-run
  python sync_operational_feeds.py
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

SCRIPT_DIR = Path(__file__).resolve().parent
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
OHGO_API_KEY = os.environ.get("OHGO_API_KEY", "").strip()
TPIMS_URLS = [
    u.strip()
    for u in os.environ.get("TPIMS_DYNAMIC_URLS", "").split(",")
    if u.strip()
]
OHGO_BASE = "https://publicapi.ohgo.com/api/v1/truck-parking"


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def fetch_poi_places(client: httpx.Client) -> list[dict[str, Any]]:
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
    }
    url = f"{SUPABASE_URL}/rest/v1/poi_places"
    params = {
        "select": "id,lat,lon,poi_type,name,external_source,external_id",
        "country_code": "eq.US",
        "limit": "50000",
    }
    resp = client.get(url, headers=headers, params=params, timeout=120.0)
    resp.raise_for_status()
    return resp.json()


def nearest_poi_id(
    places: list[dict[str, Any]],
    lat: float,
    lon: float,
    max_m: float = 400.0,
    poi_types: set[str] | None = None,
) -> str | None:
    best_id = None
    best_d = max_m
    for p in places:
        if poi_types and p.get("poi_type") not in poi_types:
            continue
        d = haversine_m(lat, lon, float(p["lat"]), float(p["lon"]))
        if d < best_d:
            best_d = d
            best_id = p["id"]
    return best_id


def normalize_operational_row(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "poi_place_id": row["poi_place_id"],
        "signal_type": row["signal_type"],
        "status_value": row["status_value"],
        "source": row["source"],
        "source_url": row.get("source_url"),
        "confidence_score": row["confidence_score"],
        "observed_at": row["observed_at"],
        "available_slots": row.get("available_slots"),
        "total_slots": row.get("total_slots"),
    }


def insert_operational(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    payload = [normalize_operational_row(r) for r in rows]
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    url = f"{SUPABASE_URL}/rest/v1/poi_operational_status"
    with httpx.Client(timeout=60.0) as client:
        batch_size = 100
        for i in range(0, len(payload), batch_size):
            chunk = payload[i : i + batch_size]
            resp = client.post(url, headers=headers, json=chunk)
            if resp.status_code >= 400:
                print(f"Insert error {resp.status_code}: {resp.text[:500]}", file=sys.stderr)
                resp.raise_for_status()


def tpims_static_url(dynamic_url: str) -> str | None:
    if "TPAS_Dynamic" in dynamic_url:
        return dynamic_url.replace("TPAS_Dynamic.json", "TPAS_Static.json").replace(
            "TPAS_Dynamic", "TPAS_Static.json"
        )
    if dynamic_url.endswith("/TPAS_Dynamic"):
        return dynamic_url.replace("/TPAS_Dynamic", "/TPAS_Static.json")
    return None


def fetch_tpims_static(client: httpx.Client, dynamic_url: str) -> dict[str, dict[str, Any]]:
    static_url = tpims_static_url(dynamic_url)
    if not static_url:
        return {}
    try:
        resp = client.get(static_url, timeout=20.0)
        resp.raise_for_status()
        data = resp.json()
    except Exception:
        return {}
    if not isinstance(data, list):
        return {}
    out: dict[str, dict[str, Any]] = {}
    for item in data:
        site_id = item.get("siteId") or item.get("site_id")
        if not site_id:
            continue
        lat = item.get("latitude") or item.get("lat")
        lon = item.get("longitude") or item.get("lon") or item.get("lng")
        if lat is None or lon is None:
            continue
        out[str(site_id)] = item
    return out


def merge_tpims_dynamic_static(
    dynamic_rows: list[dict[str, Any]],
    static_by_id: dict[str, dict[str, Any]],
    source_url: str,
) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    for row in dynamic_rows:
        site_id = row.get("external_site_id")
        static = static_by_id.get(str(site_id)) if site_id else None
        if not static:
            continue
        lat = static.get("latitude") or static.get("lat")
        lon = static.get("longitude") or static.get("lon") or static.get("lng")
        if lat is None or lon is None:
            continue
        merged.append(
            {
                "lat": float(lat),
                "lon": float(lon),
                "open": row.get("open"),
                "available": row.get("available"),
                "capacity": row.get("capacity"),
                "name": static.get("locationName")
                or static.get("name")
                or static.get("description")
                or f"TPIMS {site_id}",
                "source": "tpims",
                "source_url": source_url,
                "observed_at": row.get("observed_at"),
            }
        )
    return merged


def parse_tpims_dynamic(payload: list[dict[str, Any]], source_url: str) -> list[dict[str, Any]]:
    """I-10 / MAASTO TPIMS dynamic feed rows."""
    out: list[dict[str, Any]] = []
    now = datetime.now(timezone.utc).isoformat()
    for item in payload:
        site_id = item.get("siteId") or item.get("site_id")
        open_flag = item.get("open")
        available = item.get("reportedAvailable") or item.get("reported_available")
        capacity = item.get("capacity")
        out.append(
            {
                "external_site_id": str(site_id) if site_id else None,
                "open": open_flag,
                "available": int(available) if available is not None and str(available).isdigit() else None,
                "capacity": int(capacity) if capacity is not None and str(capacity).isdigit() else None,
                "source": "tpims",
                "source_url": source_url,
                "observed_at": item.get("timeStamp") or now,
            }
        )
    return out


def parse_ohgo(payload: dict[str, Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    items = payload.get("data") or payload.get("items") or payload
    if isinstance(items, dict):
        items = items.get("items") or []
    if not isinstance(items, list):
        return out
    for item in items:
        lat = item.get("Latitude") or item.get("latitude")
        lon = item.get("Longitude") or item.get("longitude")
        if lat is None or lon is None:
            continue
        out.append(
            {
                "lat": float(lat),
                "lon": float(lon),
                "open": item.get("Open") if "Open" in item else item.get("open"),
                "available": item.get("ReportedAvailable") or item.get("reportedAvailable"),
                "capacity": item.get("Capacity") or item.get("capacity"),
                "name": item.get("Description") or item.get("Location") or item.get("description"),
                "source": "ohgo",
                "source_url": OHGO_BASE,
                "observed_at": item.get("LastReported") or datetime.now(timezone.utc).isoformat(),
            }
        )
    return out


def build_status_rows(places: list[dict[str, Any]], signals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for sig in signals:
        poi_id = None
        if sig.get("lat") is not None and sig.get("lon") is not None:
            name = (sig.get("name") or "").lower()
            types = {"weigh_station"} if "weigh" in name or "scale" in name else None
            poi_id = nearest_poi_id(places, sig["lat"], sig["lon"], poi_types=types)
            if poi_id is None:
                poi_id = nearest_poi_id(places, sig["lat"], sig["lon"], poi_types={"truck_stop", "rest_area", "services", "weigh_station"})

        if not poi_id:
            continue

        observed_at = sig.get("observed_at") or datetime.now(timezone.utc).isoformat()
        source = sig.get("source") or "official"
        source_url = sig.get("source_url")

        open_val = sig.get("open")
        if open_val is not None:
            rows.append(
                {
                    "poi_place_id": poi_id,
                    "signal_type": "site_open",
                    "status_value": "open" if open_val else "closed",
                    "source": source,
                    "source_url": source_url,
                    "confidence_score": 0.92,
                    "observed_at": observed_at,
                }
            )
            name_lower = (sig.get("name") or "").lower()
            if "weigh" in name_lower or "scale" in name_lower:
                rows.append(
                    {
                        "poi_place_id": poi_id,
                        "signal_type": "weigh_status",
                        "status_value": "open" if open_val else "closed",
                        "source": source,
                        "source_url": source_url,
                        "confidence_score": 0.90,
                        "observed_at": observed_at,
                    }
                )

        available = sig.get("available")
        capacity = sig.get("capacity")
        if available is not None:
            rows.append(
                {
                    "poi_place_id": poi_id,
                    "signal_type": "parking_availability",
                    "status_value": "available",
                    "available_slots": available,
                    "total_slots": capacity,
                    "source": source,
                    "source_url": source_url,
                    "confidence_score": 0.88,
                    "observed_at": observed_at,
                }
            )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.dry_run and (not SUPABASE_URL or not SUPABASE_SERVICE_KEY):
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        sys.exit(1)

    signals: list[dict[str, Any]] = []

    with httpx.Client(timeout=30.0) as client:
        for url in TPIMS_URLS:
            try:
                print(f"Fetching TPIMS: {url}")
                resp = client.get(url)
                resp.raise_for_status()
                data = resp.json()
                if isinstance(data, list):
                    static_by_id = fetch_tpims_static(client, url)
                    merged = merge_tpims_dynamic_static(
                        parse_tpims_dynamic(data, url), static_by_id, url
                    )
                    signals.extend(merged)
                    print(f"  {len(merged)} TPIMS sites with geo (from {url})")
            except Exception as exc:
                print(f"  TPIMS error: {exc}", file=sys.stderr)

        if OHGO_API_KEY:
            try:
                print("Fetching OHGO truck parking…")
                resp = client.get(
                    OHGO_BASE,
                    headers={
                        "Authorization": f"APIKEY {OHGO_API_KEY}",
                        "Accept": "application/json",
                    },
                )
                resp.raise_for_status()
                parsed = parse_ohgo(resp.json())
                signals.extend(parsed)
                print(f"  {len(parsed)} OHGO sites")
            except Exception as exc:
                print(f"  OHGO error: {exc}", file=sys.stderr)
        else:
            print("OHGO_API_KEY not set — skip Ohio official parking feed")

    if args.dry_run:
        print(json.dumps(signals[:3], indent=2))
        return

    with httpx.Client(timeout=120.0) as client:
        places = fetch_poi_places(client)
        print(f"Loaded {len(places)} POIs for geo matching")
        rows = build_status_rows(places, signals)
        print(f"Inserting {len(rows)} operational status rows")
        insert_operational(rows)
    print("Done.")


if __name__ == "__main__":
    from dotenv import load_dotenv

    load_dotenv(SCRIPT_DIR / ".env")
    main()
