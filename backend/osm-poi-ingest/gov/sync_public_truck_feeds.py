#!/usr/bin/env python3
"""
Sync FREE public truck POI + operational signals (no Road511 / no paid APIs).

Sources (all $0, real-time or official static):
  - Ontario 511 REST — inspection stations, truck rest areas, ONroute service centres
    https://511on.ca/developers/doc (Open Government Licence, ~10 req/min)
  - Caltrans ArcGIS — California Commercial Vehicle Enforcement Facilities (weigh locations)
  - BC CVSE — official inspection station list (static locations, monitoring signal)
  - USDOT NTAD — via ingest_ntad.py (weekly)

Usage:
  python sync_public_truck_feeds.py --dry-run
  python sync_public_truck_feeds.py
"""

from __future__ import annotations

import argparse
import hashlib
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
BATCH_SIZE = int(os.environ.get("SUPABASE_BATCH_SIZE", "200"))

ON_INSPECTION = "https://511on.ca/api/v2/get/inspectionstations?format=json"
ON_TRUCK_REST = "https://511on.ca/api/v2/get/truckrestareas?format=json"
ON_SERVICE_CENTRES = "https://511on.ca/api/v2/get/servicecentres?format=json"
CA_CVEF = (
    "https://caltrans-gis.dot.ca.gov/arcgis/rest/services/CHhighway/"
    "Vehicle_Enforcement_Facilities/MapServer/0/query"
)
BC_CVSE_STATIONS = SCRIPT_DIR / "bc_cvse_stations.json"
BC_CVSE_SOURCE = "https://www.cvse.ca/inspection_stations.htm"
UT_UDOT_POE = SCRIPT_DIR / "ut_udot_poe.json"
UT_UDOT_SOURCE = "https://connect.udot.utah.gov/about-us/operations/motor-carriers-division/"
GOV_EXTERNAL_SOURCES = ("on511", "caltrans_cvef", "bc_cvse", "ut_udot")


def external_osm_id(source: str, external_id: str) -> int:
    digest = hashlib.sha256(f"{source}:{external_id}".encode()).hexdigest()
    return int(digest[:15], 16)


def parse_open_status(raw: Any) -> bool | None:
    if raw is None:
        return None
    if isinstance(raw, bool):
        return raw
    s = str(raw).strip().lower()
    if s in ("open", "yes", "y", "true", "1"):
        return True
    if s in ("closed", "no", "n", "false", "0", "not available"):
        return False
    if "closed" in s:
        return False
    if "open" in s:
        return True
    return None


def upsert_places(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
    }
    url = f"{SUPABASE_URL}/rest/v1/poi_places?on_conflict=external_source,external_id,poi_type"
    with httpx.Client(timeout=90.0) as client:
        for i in range(0, len(rows), BATCH_SIZE):
            resp = client.post(url, headers=headers, json=rows[i : i + BATCH_SIZE])
            if resp.status_code >= 400:
                print(resp.text[:400], file=sys.stderr)
                resp.raise_for_status()


def fetch_place_ids(client: httpx.Client) -> dict[str, str]:
    """Map external_source:external_id:poi_type → poi_places.id"""
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
    }
    out: dict[str, str] = {}
    offset = 0
    while True:
        params = {
            "select": "id,external_source,external_id,poi_type",
            "external_source": f"in.({','.join(GOV_EXTERNAL_SOURCES)})",
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


def normalize_operational_row(row: dict[str, Any]) -> dict[str, Any]:
    """PostgREST bulk insert requires identical keys on every object."""
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
    with httpx.Client(timeout=60.0) as client:
        batch_size = 100
        for i in range(0, len(payload), batch_size):
            chunk = payload[i : i + batch_size]
            resp = client.post(
                f"{SUPABASE_URL}/rest/v1/poi_operational_status",
                headers=headers,
                json=chunk,
            )
            if resp.status_code >= 400:
                print(resp.text[:500], file=sys.stderr)
                resp.raise_for_status()


def fetch_ontario(client: httpx.Client) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Returns (poi_places rows, operational signals pending poi id lookup)."""
    places: list[dict[str, Any]] = []
    pending_ops: list[dict[str, Any]] = []
    now = datetime.now(timezone.utc).isoformat()

    insp = client.get(ON_INSPECTION, timeout=30.0).json()
    for item in insp:
        ext_id = f"on-is-{item.get('Id')}"
        lat, lon = float(item["Latitude"]), float(item["Longitude"])
        name = str(item.get("Name") or "Inspection Station")
        places.append(
            {
                "osm_type": "external",
                "osm_id": external_osm_id("on511", ext_id),
                "poi_type": "weigh_station",
                "name": name,
                "operator": "Ontario MTO / CVSE",
                "lat": lat,
                "lon": lon,
                "country_code": "CA",
                "tags": {
                    "highway": item.get("Highway"),
                    "direction": item.get("Direction"),
                    "location": item.get("Location"),
                    "region": item.get("Region"),
                },
                "has_shower": False,
                "has_hgv_fuel": False,
                "has_weigh_station": True,
                "source": "on511",
                "external_source": "on511",
                "external_id": ext_id,
            }
        )
        pending_ops.append(
            {
                "key": f"on511:{ext_id}:weigh_station",
                "signal_type": "weigh_status",
                "status_value": "monitoring",
                "source": "on511:inspection",
                "source_url": ON_INSPECTION,
                "confidence_score": 0.85,
                "observed_at": now,
            }
        )

    rest = client.get(ON_TRUCK_REST, timeout=30.0).json()
    for item in rest:
        ext_id = f"on-tra-{hashlib.md5(json.dumps(item, sort_keys=True).encode()).hexdigest()[:12]}"
        lat, lon = float(item["Latitude"]), float(item["Longitude"])
        name = str(item.get("Name") or "Truck rest area")
        status_open = parse_open_status(item.get("Status"))
        truck_park = str(item.get("TruckParking", "")).upper() == "Y"
        lavatory = str(item.get("Lavatory", "")).upper() == "Y"
        places.append(
            {
                "osm_type": "external",
                "osm_id": external_osm_id("on511", ext_id),
                "poi_type": "rest_area",
                "name": name,
                "operator": "Ontario 511",
                "lat": lat,
                "lon": lon,
                "country_code": "CA",
                "tags": {
                    "roadway": item.get("Roadway"),
                    "type": item.get("Type"),
                    "truck_parking": truck_park,
                    "seasonal": item.get("Open"),
                },
                "has_shower": lavatory,
                "has_hgv_fuel": str(item.get("Fuel", "")).upper() == "Y",
                "has_weigh_station": False,
                "source": "on511",
                "external_source": "on511",
                "external_id": ext_id,
            }
        )
        if status_open is not None:
            pending_ops.append(
                {
                    "key": f"on511:{ext_id}:rest_area",
                    "signal_type": "site_open",
                    "status_value": "open" if status_open else "closed",
                    "source": "on511:truck_rest",
                    "source_url": ON_TRUCK_REST,
                    "confidence_score": 0.92,
                    "observed_at": now,
                }
            )
        if truck_park and status_open:
            pending_ops.append(
                {
                    "key": f"on511:{ext_id}:rest_area",
                    "signal_type": "parking_availability",
                    "status_value": "open" if status_open else "closed",
                    "source": "on511:truck_rest",
                    "source_url": ON_TRUCK_REST,
                    "confidence_score": 0.88,
                    "observed_at": now,
                }
            )

    centres = client.get(ON_SERVICE_CENTRES, timeout=30.0).json()
    for item in centres:
        ext_id = f"on-sc-{item.get('Id')}"
        lat, lon = float(item["Latitude"]), float(item["Longitude"])
        name = str(item.get("Name") or "ONroute Service Centre")
        parking = item.get("CommercialParking")
        try:
            total_slots = int(parking) if parking not in (None, "") else None
        except ValueError:
            total_slots = None
        places.append(
            {
                "osm_type": "external",
                "osm_id": external_osm_id("on511", ext_id),
                "poi_type": "truck_stop",
                "name": name,
                "operator": "ONroute",
                "lat": lat,
                "lon": lon,
                "country_code": "CA",
                "tags": {
                    "roadway": item.get("Roadway"),
                    "amenities": item.get("Amenities"),
                    "food": item.get("FoodServices"),
                    "fuel": item.get("FuelProvider"),
                    "website": item.get("Website"),
                },
                "has_shower": True,
                "has_hgv_fuel": bool(item.get("FuelProvider")),
                "has_weigh_station": False,
                "source": "on511",
                "external_source": "on511",
                "external_id": ext_id,
            }
        )
        if total_slots is not None:
            pending_ops.append(
                {
                    "key": f"on511:{ext_id}:truck_stop",
                    "signal_type": "parking_availability",
                    "status_value": "available",
                    "available_slots": None,
                    "total_slots": total_slots,
                    "source": "on511:service_centre",
                    "source_url": ON_SERVICE_CENTRES,
                    "confidence_score": 0.86,
                    "observed_at": now,
                }
            )

    print(f"  Ontario 511: {len(insp)} inspection, {len(rest)} truck rest, {len(centres)} service centres")
    return places, pending_ops


def fetch_bc_cvse() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """BC CVSE inspection stations — official list, no live open/closed API (Weigh2GoBC is transponder-only)."""
    if not BC_CVSE_STATIONS.is_file():
        print(f"  BC CVSE: missing {BC_CVSE_STATIONS.name}", file=sys.stderr)
        return [], []

    stations = json.loads(BC_CVSE_STATIONS.read_text(encoding="utf-8"))
    places: list[dict[str, Any]] = []
    pending_ops: list[dict[str, Any]] = []
    now = datetime.now(timezone.utc).isoformat()

    for item in stations:
        ext_id = f"bc-cvse-{item['id']}"
        lat, lon = float(item["lat"]), float(item["lon"])
        name = str(item.get("name") or "CVSE Inspection Station")
        places.append(
            {
                "osm_type": "external",
                "osm_id": external_osm_id("bc_cvse", ext_id),
                "poi_type": "weigh_station",
                "name": name,
                "operator": "BC CVSE",
                "lat": lat,
                "lon": lon,
                "country_code": "CA",
                "tags": {
                    "highway": item.get("highway"),
                    "city": item.get("city"),
                    "hours": item.get("hours"),
                },
                "has_shower": False,
                "has_hgv_fuel": False,
                "has_weigh_station": True,
                "source": "bc_cvse",
                "external_source": "bc_cvse",
                "external_id": ext_id,
            }
        )
        pending_ops.append(
            {
                "key": f"bc_cvse:{ext_id}:weigh_station",
                "signal_type": "weigh_status",
                "status_value": "monitoring",
                "source": "bc_cvse:inspection",
                "source_url": BC_CVSE_SOURCE,
                "confidence_score": 0.84,
                "observed_at": now,
            }
        )

    print(f"  BC CVSE: {len(stations)} inspection stations (monitoring signal)")
    return places, pending_ops


def fetch_utah_udot() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Utah UDOT Motor Carrier Ports of Entry — 8 full-time + part-time sites from official map."""
    if not UT_UDOT_POE.is_file():
        print(f"  Utah UDOT: missing {UT_UDOT_POE.name}", file=sys.stderr)
        return [], []

    stations = json.loads(UT_UDOT_POE.read_text(encoding="utf-8"))
    places: list[dict[str, Any]] = []
    pending_ops: list[dict[str, Any]] = []
    now = datetime.now(timezone.utc).isoformat()

    for item in stations:
        ext_id = f"ut-poe-{item['id']}"
        lat, lon = float(item["lat"]), float(item["lon"])
        name = str(item.get("name") or "Utah Port of Entry")
        full_time = bool(item.get("full_time", True))
        places.append(
            {
                "osm_type": "external",
                "osm_id": external_osm_id("ut_udot", ext_id),
                "poi_type": "weigh_station",
                "name": name,
                "operator": "Utah UDOT Motor Carrier",
                "lat": lat,
                "lon": lon,
                "country_code": "US",
                "tags": {
                    "highway": item.get("highway"),
                    "milepost": item.get("milepost"),
                    "full_time": full_time,
                    "state": "UT",
                },
                "has_shower": False,
                "has_hgv_fuel": False,
                "has_weigh_station": True,
                "source": "ut_udot",
                "external_source": "ut_udot",
                "external_id": ext_id,
            }
        )
        pending_ops.append(
            {
                "key": f"ut_udot:{ext_id}:weigh_station",
                "signal_type": "weigh_status",
                "status_value": "monitoring",
                "source": "ut_udot:poe",
                "source_url": UT_UDOT_SOURCE,
                "confidence_score": 0.88 if full_time else 0.75,
                "observed_at": now,
            }
        )

    print(f"  Utah UDOT: {len(stations)} ports of entry (monitoring — no live open/closed API)")
    return places, pending_ops


def fetch_california_cvef(client: httpx.Client) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    params = {
        "where": "1=1",
        "outFields": "FACILITY_NAME,ROUTE,DIRECTION,LOCATION,COUNTY,DISTRICT,Latitude,Longitude,OBJECTID",
        "returnGeometry": "true",
        "outSR": "4326",
        "f": "geojson",
    }
    resp = client.get(CA_CVEF, params=params, timeout=120.0)
    resp.raise_for_status()
    features = resp.json().get("features") or []
    rows: list[dict[str, Any]] = []
    pending_ops: list[dict[str, Any]] = []
    now = datetime.now(timezone.utc).isoformat()
    for f in features:
        props = f.get("properties") or {}
        geom = f.get("geometry") or {}
        coords = geom.get("coordinates") or []
        if len(coords) >= 2:
            lon, lat = float(coords[0]), float(coords[1])
        else:
            lat = props.get("Latitude")
            lon = props.get("Longitude")
            if lat is None or lon is None:
                continue
            lat, lon = float(lat), float(lon)
        oid = props.get("OBJECTID")
        ext_id = f"ca-cvef-{oid}"
        name = str(props.get("FACILITY_NAME") or "Caltrans Weigh Station")
        rows.append(
            {
                "osm_type": "external",
                "osm_id": external_osm_id("caltrans_cvef", ext_id),
                "poi_type": "weigh_station",
                "name": name,
                "operator": "Caltrans / CHP",
                "lat": lat,
                "lon": lon,
                "country_code": "US",
                "tags": {
                    "route": props.get("ROUTE"),
                    "direction": props.get("DIRECTION"),
                    "location": props.get("LOCATION"),
                    "county": props.get("COUNTY"),
                },
                "has_shower": False,
                "has_hgv_fuel": False,
                "has_weigh_station": True,
                "source": "caltrans_cvef",
                "external_source": "caltrans_cvef",
                "external_id": ext_id,
            }
        )
        pending_ops.append(
            {
                "key": f"caltrans_cvef:{ext_id}:weigh_station",
                "signal_type": "weigh_status",
                "status_value": "monitoring",
                "source": "caltrans_cvef",
                "source_url": CA_CVEF,
                "confidence_score": 0.82,
                "observed_at": now,
            }
        )
    print(f"  Caltrans CVEF: {len(rows)} weigh facilities")
    return rows, pending_ops


def attach_ops(pending: list[dict[str, Any]], id_map: dict[str, str]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for p in pending:
        poi_id = id_map.get(p.pop("key"))
        if not poi_id:
            continue
        p["poi_place_id"] = poi_id
        rows.append(p)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--ontario-only", action="store_true")
    args = parser.parse_args()

    if not args.dry_run and (not SUPABASE_URL or not SUPABASE_SERVICE_KEY):
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        sys.exit(1)

    places: list[dict[str, Any]] = []
    pending_ops: list[dict[str, Any]] = []

    with httpx.Client() as client:
        print("Fetching Ontario 511 (free, real-time)…")
        on_places, on_ops = fetch_ontario(client)
        places.extend(on_places)
        pending_ops.extend(on_ops)

        print("Fetching BC CVSE inspection stations (official static list)…")
        bc_places, bc_ops = fetch_bc_cvse()
        places.extend(bc_places)
        pending_ops.extend(bc_ops)

        print("Fetching Utah UDOT ports of entry (official static list)…")
        ut_places, ut_ops = fetch_utah_udot()
        places.extend(ut_places)
        pending_ops.extend(ut_ops)

        if not args.ontario_only:
            print("Fetching Caltrans CVEF (free, static locations)…")
            ca_places, ca_ops = fetch_california_cvef(client)
            places.extend(ca_places)
            pending_ops.extend(ca_ops)

    print(f"Total POI rows: {len(places)}")
    if args.dry_run:
        print(json.dumps(places[:2], indent=2))
        print(f"Pending ops: {len(pending_ops)}")
        return

    upsert_places(places)
    print(f"  Upserted {len(places)} poi_places rows")
    with httpx.Client(timeout=120.0) as client:
        id_map = fetch_place_ids(client)
        print(f"  Resolved {len(id_map)} gov POI ids in Supabase")
        ops = attach_ops(pending_ops, id_map)
        print(f"Inserting {len(ops)} operational signals")
        insert_operational(ops)
    print("Done.")


if __name__ == "__main__":
    from dotenv import load_dotenv

    load_dotenv(SCRIPT_DIR / ".env")
    load_dotenv(SCRIPT_DIR.parent / ".env")  # ~/osm-poi-ingest/.env on EC2
    main()
