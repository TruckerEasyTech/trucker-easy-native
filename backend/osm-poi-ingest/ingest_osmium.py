#!/usr/bin/env python3
"""Extract truck-relevant POIs from the Valhalla US+Canada PBF and upsert to Supabase.

Run this on the Valhalla EC2 to avoid public Overpass limits:

  sudo apt-get update && sudo apt-get install -y osmium-tool
  python3 -m venv .venv
  . .venv/bin/activate
  pip install httpx
  export SUPABASE_URL=https://YOUR_PROJECT.supabase.co
  export SUPABASE_SERVICE_ROLE_KEY=...
  python3 ingest_osmium.py --dry-run
  python3 ingest_osmium.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import httpx

DEFAULT_PBF = Path("/opt/valhalla/custom_files/us-canada.osm.pbf")
WORK_DIR = Path(os.environ.get("OSM_INGEST_WORKDIR", str(Path.home() / "osm-poi-ingest" / "tmp")))
OUT_PBF = WORK_DIR / "truck-pois-filtered.osm.pbf"
OUT_GEOJSON = WORK_DIR / "truck-pois-filtered.geojson"
BATCH_SIZE = int(os.environ.get("SUPABASE_BATCH_SIZE", "500"))
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

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
    if tags.get("highway") == "weigh_station" or tags.get("amenity") in ("weigh_station", "weighbridge"):
        return "weigh_station"
    if tags.get("highway") == "rest_area":
        return "rest_area"
    if tags.get("highway") == "services" and tags.get("hgv") in ("yes", "designated"):
        return "services"
    if tags.get("amenity") == "truck_stop":
        return "truck_stop"
    if tags.get("amenity") == "fuel":
        hgv = tags.get("hgv", "")
        if hgv in ("yes", "designated") or tags.get("fuel:HGV_diesel") == "yes" or tags.get("motorcar") == "no":
            return "fuel"
    return None


def geometry_center(geometry: dict[str, Any]) -> tuple[float, float] | None:
    gtype = geometry.get("type")
    coords = geometry.get("coordinates")
    if gtype == "Point" and isinstance(coords, list) and len(coords) >= 2:
        return float(coords[1]), float(coords[0])

    points: list[tuple[float, float]] = []

    def collect(value: Any) -> None:
        if (
            isinstance(value, list)
            and len(value) >= 2
            and all(isinstance(n, (int, float)) for n in value[:2])
        ):
            points.append((float(value[1]), float(value[0])))
            return
        if isinstance(value, list):
            for item in value:
                collect(item)

    collect(coords)
    if not points:
        return None
    lat = sum(p[0] for p in points) / len(points)
    lon = sum(p[1] for p in points) / len(points)
    return lat, lon


def feature_to_row(feature: dict[str, Any]) -> dict[str, Any] | None:
    props = feature.get("properties") or {}
    tags = {k: str(v) for k, v in props.items() if v is not None}
    poi_type = classify_poi(tags)
    if not poi_type:
        return None

    center = geometry_center(feature.get("geometry") or {})
    if center is None:
        return None
    lat, lon = center

    name = tags.get("name") or tags.get("brand") or tags.get("operator")
    brand = tags.get("brand")
    operator = tags.get("operator")

    fid = str(feature.get("id") or props.get("@id") or props.get("id") or "")
    osm_type = "node"
    osm_id_raw = fid
    if "/" in fid:
        osm_type, osm_id_raw = fid.split("/", 1)
    if not osm_id_raw:
        digest = hashlib.sha256(
            f"{lat}:{lon}:{name or ''}:{poi_type}:{json.dumps(tags, sort_keys=True)}".encode()
        ).hexdigest()
        osm_id = int(digest[:15], 16)
        osm_type = "external"
    else:
        try:
            osm_id = int(re.sub(r"\D", "", osm_id_raw))
        except ValueError:
            return None

    network = detect_network(name or "", brand, operator)

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
        "country_code": "US" if 24 <= lat <= 49.5 and -125 <= lon <= -66 else "CA",
        "tags": tags,
        "has_shower": tags.get("shower") in ("yes", "1", "true"),
        "has_hgv_fuel": poi_type in ("fuel", "truck_stop", "services"),
        "has_weigh_station": poi_type == "weigh_station" or tags.get("amenity") == "weighbridge",
        "source": "osm_pbf",
    }


def upsert_supabase(rows: list[dict[str, Any]]) -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY")

    seen: set[tuple[str, int, str]] = set()
    deduped: list[dict[str, Any]] = []
    for row in rows:
        key = (row["osm_type"], row["osm_id"], row["poi_type"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(row)
    if len(deduped) < len(rows):
        print(f"  Deduped {len(rows) - len(deduped)} duplicate OSM rows", flush=True)
    rows = deduped
    if not rows:
        return
    url = f"{SUPABASE_URL}/rest/v1/poi_places"
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    params = {"on_conflict": "osm_type,osm_id,poi_type"}
    with httpx.Client(timeout=120.0) as client:
        for i in range(0, len(rows), BATCH_SIZE):
            chunk = rows[i : i + BATCH_SIZE]
            r = client.post(url, headers=headers, params=params, json=chunk)
            if r.status_code >= 400:
                raise RuntimeError(f"Supabase upsert failed {r.status_code}: {r.text[:500]}")
            print(f"  uploaded {min(i + BATCH_SIZE, len(rows))}/{len(rows)}", flush=True)


def run(cmd: list[str]) -> None:
    print("Running:", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="PBF/osmium POI ingest -> Supabase")
    parser.add_argument("pbf", nargs="?", default=str(DEFAULT_PBF))
    parser.add_argument("--dry-run", action="store_true", help="Extract and count only, no Supabase upload")
    parser.add_argument("--skip-filter", action="store_true", help="Reuse /tmp/truck-pois-filtered.osm.pbf")
    args = parser.parse_args()

    pbf = Path(args.pbf)
    if not pbf.is_file():
        print(f"PBF not found: {pbf}", file=sys.stderr)
        print("Run on EC2 after Valhalla deploy, or pass path to local extract.", file=sys.stderr)
        return 1

    WORK_DIR.mkdir(parents=True, exist_ok=True)

    if not args.skip_filter:
        run([
            "osmium", "tags-filter", str(pbf),
            "n/amenity=truck_stop",
            "n/amenity=fuel",
            "w/amenity=fuel",
            "n/highway=services",
            "w/highway=services",
            "n/highway=rest_area",
            "w/highway=rest_area",
            "n/highway=weigh_station",
            "w/highway=weigh_station",
            "-o", str(OUT_PBF),
            "--overwrite",
        ])

    run(["osmium", "export", str(OUT_PBF), "-f", "geojson", "-o", str(OUT_GEOJSON), "--overwrite", "--attributes=id"])
    payload = json.loads(OUT_GEOJSON.read_text(encoding="utf-8"))
    rows = [
        row
        for feature in payload.get("features", [])
        if (row := feature_to_row(feature))
    ]
    print(f"Prepared {len(rows)} truck POI rows from {OUT_GEOJSON}", flush=True)
    if rows[:3]:
        print(json.dumps(rows[:3], indent=2)[:1200], flush=True)

    if args.dry_run:
        print("Dry-run only. No Supabase upload.", flush=True)
        return 0

    upsert_supabase(rows)
    print("Done.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
