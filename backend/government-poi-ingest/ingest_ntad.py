#!/usr/bin/env python3
"""
Ingest USDOT NTAD (public domain) truck parking + WIM weigh station locations into Supabase poi_places.

HERE and Trucker Path use licensed POI databases; NTAD is the free federal baseline (Jason's Law / FHWA).
Real-time weigh OPEN/CLOSED is not published nationally — crowd + state TPIMS/OHGO feeds handle that separately.

Usage:
  cp .env.example .env
  pip install -r requirements.txt
  python ingest_ntad.py --dry-run
  python ingest_ntad.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import httpx

SCRIPT_DIR = Path(__file__).resolve().parent
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
BATCH_SIZE = int(os.environ.get("SUPABASE_BATCH_SIZE", "200"))

NTAD_TRUCK_PARKING = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/ArcGIS/rest/services/"
    "NTAD_Truck_Stop_Parking/FeatureServer/0/query"
)
NTAD_WIM = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/"
    "NTAD_Weigh_in_Motion_Stations/FeatureServer/0/query"
)
NTAD_WIM_SOURCE = "https://doi.org/10.21949/7e9e-gw75"


def external_osm_id(source: str, external_id: str) -> int:
    digest = hashlib.sha256(f"{source}:{external_id}".encode()).hexdigest()
    return int(digest[:15], 16)


def arcgis_fetch_all(client: httpx.Client, url: str, page_size: int = 2000) -> list[dict[str, Any]]:
    features: list[dict[str, Any]] = []
    offset = 0
    while True:
        params = {
            "where": "1=1",
            "outFields": "*",
            "returnGeometry": "true",
            "f": "geojson",
            "resultRecordCount": str(page_size),
            "resultOffset": str(offset),
        }
        resp = client.get(url, params=params, timeout=120.0)
        resp.raise_for_status()
        data = resp.json()
        batch = data.get("features") or []
        if not batch:
            break
        features.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size
        time.sleep(0.5)
    return features


def ntad_parking_row(feature: dict[str, Any]) -> dict[str, Any] | None:
    props = feature.get("properties") or {}
    geom = feature.get("geometry") or {}
    coords = geom.get("coordinates") or []
    if len(coords) < 2:
        lat = props.get("latitude")
        lon = props.get("longitude")
        if lat is None or lon is None:
            return None
    else:
        lon, lat = float(coords[0]), float(coords[1])

    object_id = props.get("OBJECTID")
    if object_id is None:
        return None
    ext_id = f"ntad-parking-{object_id}"
    name = (props.get("nhs_rest_stop") or props.get("name") or "Truck parking").strip()
    highway = props.get("highway_route") or ""
    state = props.get("state") or "US"
    spots = props.get("number_of_spots")

    poi_type = "rest_area"
    lower_name = name.lower()
    if "weigh" in lower_name or "scale" in lower_name or "inspection" in lower_name:
        poi_type = "weigh_station"
    elif "truck" in lower_name and "stop" in lower_name:
        poi_type = "truck_stop"

    tags = {
        "ntad": True,
        "highway_route": highway,
        "mile_post": props.get("mile_post"),
        "county": props.get("county"),
        "municipality": props.get("municipality"),
        "number_of_spots": spots,
    }

    return {
        "osm_type": "external",
        "osm_id": external_osm_id("ntad", ext_id),
        "poi_type": poi_type,
        "name": name,
        "brand": None,
        "operator": "USDOT NTAD",
        "network": None,
        "lat": float(lat),
        "lon": float(lon),
        "country_code": "US",
        "tags": tags,
        "has_shower": False,
        "has_hgv_fuel": False,
        "has_weigh_station": poi_type == "weigh_station",
        "source": "ntad",
        "external_source": "ntad",
        "external_id": ext_id,
    }


def ntad_wim_row(feature: dict[str, Any]) -> dict[str, Any] | None:
    props = feature.get("properties") or {}
    geom = feature.get("geometry") or {}
    coords = geom.get("coordinates") or []
    if len(coords) < 2:
        lat = props.get("latitude")
        lon = props.get("longitude")
        if lat is None or lon is None:
            return None
    else:
        lon, lat = float(coords[0]), float(coords[1])

    station_id = props.get("station_id") or props.get("Concat_ID")
    if not station_id:
        return None
    ext_id = f"ntad-wim-{station_id}"
    state = props.get("state") or "US"
    name = f"{state} WIM {station_id}"

    tags = {
        "ntad_wim": True,
        "station_id": station_id,
        "functional_class": props.get("functional_class"),
        "counts_year": props.get("Counts_Year"),
        "num_days_active": props.get("Num_Days_Active"),
    }

    return {
        "osm_type": "external",
        "osm_id": external_osm_id("ntad_wim", ext_id),
        "poi_type": "weigh_station",
        "name": name,
        "brand": None,
        "operator": f"{state} DOT / FHWA WIM",
        "network": None,
        "lat": float(lat),
        "lon": float(lon),
        "country_code": "US",
        "tags": tags,
        "has_shower": False,
        "has_hgv_fuel": False,
        "has_weigh_station": True,
        "source": "ntad_wim",
        "external_source": "ntad_wim",
        "external_id": ext_id,
    }


def upsert_batch(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
    }
    url = f"{SUPABASE_URL}/rest/v1/poi_places?on_conflict=external_source,external_id,poi_type"
    with httpx.Client(timeout=60.0) as client:
        for i in range(0, len(rows), BATCH_SIZE):
            chunk = rows[i : i + BATCH_SIZE]
            resp = client.post(url, headers=headers, json=chunk)
            if resp.status_code >= 400:
                print(f"Upsert error {resp.status_code}: {resp.text[:500]}", file=sys.stderr)
                resp.raise_for_status()


def fetch_place_ids(client: httpx.Client, sources: tuple[str, ...]) -> dict[str, str]:
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
    }
    out: dict[str, str] = {}
    offset = 0
    while True:
        params = {
            "select": "id,external_source,external_id,poi_type",
            "external_source": f"in.({','.join(sources)})",
            "limit": "1000",
            "offset": str(offset),
        }
        resp = client.get(f"{SUPABASE_URL}/rest/v1/poi_places", headers=headers, params=params)
        resp.raise_for_status()
        batch = resp.json()
        if not batch:
            break
        for row in batch:
            key = f"{row['external_source']}:{row['external_id']}:{row['poi_type']}"
            out[key] = row["id"]
        if len(batch) < 1000:
            break
        offset += 1000
    return out


def insert_operational(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    with httpx.Client(timeout=60.0) as client:
        for i in range(0, len(rows), 100):
            chunk = rows[i : i + 100]
            resp = client.post(f"{SUPABASE_URL}/rest/v1/poi_operational_status", headers=headers, json=chunk)
            if resp.status_code >= 400:
                print(resp.text[:500], file=sys.stderr)
                resp.raise_for_status()


def attach_wim_ops(wim_rows: list[dict[str, Any]], id_map: dict[str, str]) -> list[dict[str, Any]]:
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc).isoformat()
    out: list[dict[str, Any]] = []
    for row in wim_rows:
        key = f"ntad_wim:{row['external_id']}:weigh_station"
        poi_id = id_map.get(key)
        if not poi_id:
            continue
        out.append(
            {
                "poi_place_id": poi_id,
                "signal_type": "weigh_status",
                "status_value": "monitoring",
                "source": "ntad_wim",
                "source_url": NTAD_WIM_SOURCE,
                "confidence_score": 0.80,
                "observed_at": now,
            }
        )
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest NTAD truck parking + WIM into poi_places")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.dry_run and (not SUPABASE_URL or not SUPABASE_SERVICE_KEY):
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env", file=sys.stderr)
        sys.exit(1)

    rows: list[dict[str, Any]] = []
    wim_rows: list[dict[str, Any]] = []
    with httpx.Client() as client:
        print("Fetching NTAD truck parking…")
        parking_features = arcgis_fetch_all(client, NTAD_TRUCK_PARKING)
        for f in parking_features:
            row = ntad_parking_row(f)
            if row:
                rows.append(row)
        print(f"  parking/rest features: {len(parking_features)} → {sum(1 for r in rows if r['external_source']=='ntad')} rows")

        print("Fetching NTAD WIM weigh stations…")
        wim_features = arcgis_fetch_all(client, NTAD_WIM)
        for f in wim_features:
            row = ntad_wim_row(f)
            if row:
                rows.append(row)
                wim_rows.append(row)
        print(f"  WIM features: {len(wim_features)} → {len(wim_rows)} weigh rows")

    # A fonte NTAD contém ids duplicados no mesmo dataset → o Postgres rejeita o lote inteiro
    # ("ON CONFLICT DO UPDATE cannot affect row a second time", SQLSTATE 21000). Dedup pela
    # chave de conflito (external_source, external_id, poi_type), mantendo a última ocorrência.
    unique: dict[tuple[str, str, str], dict[str, Any]] = {}
    for r in rows:
        unique[(r["external_source"], r["external_id"], r["poi_type"])] = r
    if len(unique) != len(rows):
        print(f"Deduped {len(rows)} → {len(unique)} rows (fonte NTAD tem ids repetidos)")
    rows = list(unique.values())

    print(f"Total rows to upsert: {len(rows)}")
    if args.dry_run:
        print(json.dumps(rows[:2], indent=2))
        print(f"Would attach {len(wim_rows)} WIM monitoring signals")
        return

    upsert_batch(rows)
    if wim_rows:
        with httpx.Client(timeout=120.0) as client:
            id_map = fetch_place_ids(client, ("ntad_wim",))
            ops = attach_wim_ops(wim_rows, id_map)
            print(f"Inserting {len(ops)} NTAD WIM monitoring signals")
            insert_operational(ops)
    print("Done.")


if __name__ == "__main__":
    from dotenv import load_dotenv

    load_dotenv(SCRIPT_DIR / ".env")
    main()
