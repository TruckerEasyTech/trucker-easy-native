#!/usr/bin/env python3
"""
Ingest truck-relevant OSM POIs (US + Canada tiles) via Overpass → Supabase poi_places.

Usage:
  cp .env.example .env   # fill SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
  pip install -r requirements.txt
  python ingest_overpass.py --dry-run              # one region, no upload
  python ingest_overpass.py --region us-tx         # single state/province
  python ingest_overpass.py --all                  # all regions in regions_us_ca.json

Respect Overpass fair-use: pause between regions (default 25s). Run weekly, not on every app open.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

import httpx

SCRIPT_DIR = Path(__file__).resolve().parent
REGIONS_FILE = SCRIPT_DIR / "regions_us_ca.json"

OVERPASS_URLS = [
    url.strip()
    for url in os.environ.get(
        "OVERPASS_URLS",
        os.environ.get(
            "OVERPASS_URL",
            "https://overpass-api.de/api/interpreter,https://overpass.kumi.systems/api/interpreter",
        ),
    ).split(",")
    if url.strip()
]
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
PAUSE_SECONDS = float(os.environ.get("OVERPASS_PAUSE_SECONDS", "25"))
BATCH_SIZE = int(os.environ.get("SUPABASE_BATCH_SIZE", "200"))

# Road signage (traffic signals + stop signs) for in-city route-aware navigation.
# OPT-IN: these nodes are EXTREMELY dense (millions across US+CA). Enable only when ingesting
# the metro/city tiles you actually navigate, never for a nationwide sweep, or it will blow up
# the poi_places table and trip Overpass timeouts. Set INGEST_SIGNAGE=1 to include them.
INGEST_SIGNAGE = os.environ.get("INGEST_SIGNAGE", "0").lower() in ("1", "true", "yes")
SIGNAGE_QUERY_LINES = """  node["highway"="traffic_signals"]({south},{west},{north},{east});
  node["highway"="stop"]({south},{west},{north},{east});
"""

OVERPASS_QUERY = """
[out:json][timeout:180];
(
  node["amenity"="truck_stop"]({south},{west},{north},{east});
  way["amenity"="truck_stop"]({south},{west},{north},{east});
  node["amenity"="fuel"]["hgv"~"yes|designated"]({south},{west},{north},{east});
  way["amenity"="fuel"]["hgv"~"yes|designated"]({south},{west},{north},{east});
  node["amenity"="fuel"]["brand"~"Pilot|Love.?s|TA|Petro|Flying J|Kwik Trip|Sapp",i]({south},{west},{north},{east});
  way["amenity"="fuel"]["brand"~"Pilot|Love.?s|TA|Petro|Flying J|Kwik Trip|Sapp",i]({south},{west},{north},{east});
  node["highway"="services"]["hgv"="yes"]({south},{west},{north},{east});
  way["highway"="services"]["hgv"="yes"]({south},{west},{north},{east});
  node["highway"="rest_area"]({south},{west},{north},{east});
  way["highway"="rest_area"]({south},{west},{north},{east});
  node["highway"="weigh_station"]({south},{west},{north},{east});
  way["highway"="weigh_station"]({south},{west},{north},{east});
  node["amenity"="weighbridge"]({south},{west},{north},{east});
  way["amenity"="weighbridge"]({south},{west},{north},{east});
);
out center;
"""

NETWORK_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("pilot", re.compile(r"pilot|flying\s*j", re.I)),
    ("loves", re.compile(r"love'?s|loves", re.I)),
    ("ta", re.compile(r"\bta\b|travel\s*cent", re.I)),
    ("petro", re.compile(r"petro", re.I)),
    ("sapp", re.compile(r"sapp\s*bros", re.I)),
]


def detect_network(name: str, brand: str | None, operator: str | None) -> str | None:
    blob = " ".join(filter(None, [name, brand, operator]))
    for slug, pat in NETWORK_PATTERNS:
        if pat.search(blob):
            return slug
    return None


def classify_poi(tags: dict[str, str]) -> str | None:
    if tags.get("highway") == "weigh_station" or tags.get("amenity") == "weighbridge":
        return "weigh_station"
    if tags.get("amenity") == "shower":
        return "shower"
    if tags.get("highway") == "rest_area":
        return "rest_area"
    if tags.get("amenity") == "truck_stop":
        return "truck_stop"
    if tags.get("highway") == "services" and tags.get("hgv") == "yes":
        return "services"
    if tags.get("highway") == "traffic_signals":
        return "traffic_signals"
    if tags.get("highway") == "stop":
        return "stop"
    if tags.get("amenity") == "fuel":
        name = tags.get("name") or tags.get("brand") or tags.get("operator") or ""
        network = detect_network(name, tags.get("brand"), tags.get("operator"))
        hgv = tags.get("hgv", "")
        if network is not None or hgv in ("yes", "designated") or tags.get("motorcar") == "no":
            return "truck_stop" if network is not None else "fuel"
    return None


def element_to_row(el: dict[str, Any], country: str) -> dict[str, Any] | None:
    tags = el.get("tags") or {}
    poi_type = classify_poi(tags)
    if not poi_type:
        return None

    osm_type = el["type"]
    osm_id = int(el["id"])

    if osm_type == "node":
        lat, lon = float(el["lat"]), float(el["lon"])
    else:
        center = el.get("center") or {}
        if "lat" not in center or "lon" not in center:
            return None
        lat, lon = float(center["lat"]), float(center["lon"])

    name = tags.get("name") or tags.get("brand") or tags.get("operator")
    brand = tags.get("brand")
    operator = tags.get("operator")
    network = detect_network(name or "", brand, operator)

    has_shower = (
        poi_type == "shower"
        or tags.get("shower") in ("yes", "1", "true")
        or tags.get("amenity") == "shower"
    )
    has_hgv_fuel = poi_type in ("fuel", "truck_stop", "services")
    has_weigh = poi_type == "weigh_station" or tags.get("amenity") == "weighbridge"

    return {
        "osm_type": osm_type,
        "osm_id": osm_id,
        "poi_type": poi_type,
        "name": name,
        "brand": brand,
        "operator": operator,
        "network": network,
        "lat": lat,
        "lon": lon,
        "country_code": country,
        "tags": tags,
        "has_shower": has_shower,
        "has_hgv_fuel": has_hgv_fuel,
        "has_weigh_station": has_weigh,
        "source": "osm",
        "last_seen_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


def fetch_overpass(bbox: list[float]) -> dict[str, Any]:
    south, west, north, east = bbox
    template = OVERPASS_QUERY
    if INGEST_SIGNAGE:
        # Inject the signage node queries just before the union's closing "\n);" (the only place
        # ");" sits at the start of a line — every query line ends with ");" instead).
        template = template.replace("\n);", "\n" + SIGNAGE_QUERY_LINES + ");", 1)
    query = template.format(
        south=south, west=west, north=north, east=east
    )
    headers = {"User-Agent": "TruckerEasyPOIIngest/1.0 (contact: ops@truckereasy.com)"}
    last_error: Exception | None = None
    for url in OVERPASS_URLS:
        try:
            with httpx.Client(timeout=httpx.Timeout(200.0, connect=30.0), headers=headers) as client:
                r = client.post(url, data={"data": query})
                if r.status_code >= 400:
                    detail = r.text[:500].replace("\n", " ")
                    raise httpx.HTTPStatusError(
                        f"{r.status_code} from {url}: {detail}",
                        request=r.request,
                        response=r,
                    )
                return r.json()
        except (httpx.HTTPError, httpx.TimeoutException) as e:
            last_error = e
            print(f"    Overpass mirror failed: {e}", file=sys.stderr, flush=True)
            time.sleep(3)
    if last_error:
        raise last_error
    raise RuntimeError("No Overpass URL configured")


def upsert_supabase(rows: list[dict[str, Any]]) -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env")

    url = f"{SUPABASE_URL}/rest/v1/poi_places"
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    params = {"on_conflict": "osm_type,osm_id,poi_type"}

    with httpx.Client(timeout=60.0) as client:
        for i in range(0, len(rows), BATCH_SIZE):
            chunk = rows[i : i + BATCH_SIZE]
            r = client.post(url, headers=headers, params=params, json=chunk)
            if r.status_code >= 400:
                raise RuntimeError(f"Supabase upsert failed {r.status_code}: {r.text[:500]}")


def load_regions() -> list[dict[str, Any]]:
    data = json.loads(REGIONS_FILE.read_text(encoding="utf-8"))
    return data["regions"]


def run_region(region: dict[str, Any], dry_run: bool) -> int:
    rid = region["id"]
    bbox = region["bbox"]
    country = region.get("country", "US")
    print(f"  [{rid}] Overpass {bbox} …", flush=True)

    payload = fetch_overpass(bbox)
    elements = payload.get("elements") or []
    rows: list[dict[str, Any]] = []
    for el in elements:
        row = element_to_row(el, country)
        if row:
            rows.append(row)

    print(f"  [{rid}] {len(rows)} POIs (from {len(elements)} elements)", flush=True)

    if dry_run:
        if rows:
            print(f"  sample: {json.dumps(rows[0], indent=2)[:400]}…")
        return len(rows)

    if rows:
        upsert_supabase(rows)
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="OSM POI ingest → Supabase")
    parser.add_argument("--region", help="Single region id (e.g. us-tx)")
    parser.add_argument("--all", action="store_true", help="All regions in JSON")
    parser.add_argument("--dry-run", action="store_true", help="Fetch only, no Supabase")
    parser.add_argument("--pause", type=float, default=PAUSE_SECONDS)
    args = parser.parse_args()

    regions = load_regions()
    if args.region:
        regions = [r for r in regions if r["id"] == args.region]
        if not regions:
            print(f"Unknown region: {args.region}", file=sys.stderr)
            return 1
    elif not args.all:
        regions = regions[:1]
        print("Tip: use --all for full US+CA tiles, or --region us-tx", flush=True)

    total = 0
    for i, region in enumerate(regions):
        try:
            total += run_region(region, args.dry_run)
        except httpx.HTTPError as e:
            print(f"  [{region['id']}] HTTP error: {e}", file=sys.stderr)
        if i < len(regions) - 1 and not args.dry_run:
            print(f"  pausing {args.pause}s (Overpass fair-use)…", flush=True)
            time.sleep(args.pause)

    print(f"Done. {total} POI rows processed.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
