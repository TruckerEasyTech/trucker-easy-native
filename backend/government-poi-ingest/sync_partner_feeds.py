#!/usr/bin/env python3
"""
Sync official trucking POI + operational status into Supabase via Edge Function.

Sources (Edge secrets):
  - ROAD511_API_KEY  → state 511 / DOT / NBI weigh + truck parking (open/closed where published)
  - NEXTBILLION_API_KEY → Browse API truck_stop / rest_area / fuel POI catalog

Run every 10–15 min on EC2 alongside sync_operational_feeds.py.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REGIONS_FILE = Path(__file__).resolve().parents[1] / "osm-poi-ingest" / "regions_us_ca.json"


def env(name: str, required: bool = True) -> str:
    val = os.environ.get(name, "").strip()
    if required and not val:
        print(f"Missing {name}", file=sys.stderr)
        sys.exit(1)
    return val


def region_centers(regions_path: Path) -> list[tuple[str, float, float]]:
    data = json.loads(regions_path.read_text())
    out: list[tuple[str, float, float]] = []
    for region in data.get("regions", []):
        south, west, north, east = region["bbox"]
        lat = (south + north) / 2
        lon = (west + east) / 2
        out.append((region.get("id", "region"), lat, lon))
    return out


def call_trucking_poi_feed(base_url: str, anon_key: str, lat: float, lon: float) -> dict:
    qs = urllib.parse.urlencode(
        {"lat": lat, "lon": lon, "radius_km": 80, "persist": "1"},
    )
    url = f"{base_url.rstrip('/')}/functions/v1/trucking-poi-feed?{qs}"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "apikey": anon_key,
            "Authorization": f"Bearer {anon_key}",
        },
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.loads(resp.read().decode())


def main() -> None:
    supabase_url = env("SUPABASE_URL")
    anon_key = env("SUPABASE_ANON_KEY")
    if not os.environ.get("ROAD511_API_KEY") and not os.environ.get("NEXTBILLION_API_KEY"):
        print(
            "Set ROAD511_API_KEY and/or NEXTBILLION_API_KEY in Supabase Edge secrets "
            "(Dashboard → Edge Functions → Secrets). This script only triggers sync.",
            file=sys.stderr,
        )

    centers = region_centers(REGIONS_FILE)
    print(f"Syncing {len(centers)} corridor centers via trucking-poi-feed…")

    total_places = 0
    total_weigh = 0
    for region_id, lat, lon in centers:
        try:
            payload = call_trucking_poi_feed(supabase_url, anon_key, lat, lon)
            places = len(payload.get("places") or [])
            weigh = len(payload.get("weigh_signals") or [])
            sources = ",".join(payload.get("sources") or [])
            total_places += places
            total_weigh += weigh
            print(f"  {region_id}: places={places} weigh={weigh} sources=[{sources}]")
        except urllib.error.HTTPError as e:
            print(f"  {region_id}: HTTP {e.code}", file=sys.stderr)
        except Exception as e:
            print(f"  {region_id}: {e}", file=sys.stderr)
        time.sleep(0.35)

    print(f"Done. places={total_places} weigh_signals={total_weigh}")


if __name__ == "__main__":
    main()
