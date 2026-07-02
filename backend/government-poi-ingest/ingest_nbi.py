#!/usr/bin/env python3
"""
Ingest FHWA NBI (National Bridge Inventory) — PONTES BAIXAS → Supabase poi_places.

Fonte: NTAD_National_Bridge_Inventory (ArcGIS público do USDOT, domínio público).
Filtro: altura livre restritiva < 4.9m (16ft) —
  • VERT_CLR_UND_054B (ref 'H'): vão livre da RODOVIA QUE PASSA POR BAIXO da ponte
    (o risco clássico de caminhão 13'6" bater na estrutura), ou
  • VERT_CLR_OVER_MT_053: restrição vertical NO tabuleiro (treliça/pórtico).
Cada linha vira poi_places poi_type="low_bridge" com clearance em metros e pés
nas tags — dado federal real, nunca estimado. 99.99m = sem restrição (excluído
pelo filtro server-side).

Usage:
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... python3 ingest_nbi.py --dry-run
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... python3 ingest_nbi.py
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
from typing import Any

import httpx

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
BATCH_SIZE = int(os.environ.get("SUPABASE_BATCH_SIZE", "200"))

NBI_LAYER = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/"
    "NTAD_National_Bridge_Inventory/FeatureServer/0/query"
)
# Restritivo para caminhão: < 4.9m (16ft). 13'6" padrão = 4.11m; margem cobre oversize.
LOW_CLEARANCE_WHERE = (
    "((VERT_CLR_UND_REF_054A='H' AND VERT_CLR_UND_054B>0 AND VERT_CLR_UND_054B<4.9) "
    "OR (VERT_CLR_OVER_MT_053>0 AND VERT_CLR_OVER_MT_053<4.9))"
)
OUT_FIELDS = ",".join([
    "STRUCTURE_NUMBER_008", "STATE_CODE_001", "FACILITY_CARRIED_007",
    "FEATURES_DESC_006A", "LOCATION_009",
    "VERT_CLR_UND_054B", "VERT_CLR_UND_REF_054A", "VERT_CLR_OVER_MT_053",
])


def external_osm_id(source: str, external_id: str) -> int:
    digest = hashlib.sha256(f"{source}:{external_id}".encode()).hexdigest()
    return int(digest[:15], 16)


def fetch_low_bridges(client: httpx.Client) -> list[dict[str, Any]]:
    features: list[dict[str, Any]] = []
    offset = 0
    while True:
        params = {
            "where": LOW_CLEARANCE_WHERE,
            "outFields": OUT_FIELDS,
            "returnGeometry": "true",
            "outSR": "4326",
            "resultOffset": offset,
            "resultRecordCount": 2000,
            "f": "json",
        }
        resp = client.get(NBI_LAYER, params=params, timeout=180.0)
        resp.raise_for_status()
        data = resp.json()
        page = data.get("features", [])
        features.extend(page)
        print(f"  página offset={offset}: +{len(page)} (total {len(features)})")
        if len(page) < 2000:
            break
        offset += 2000
    return features


def meters_to_ftin(m: float) -> str:
    total_in = m / 0.0254
    ft = int(total_in // 12)
    inch = int(round(total_in - ft * 12))
    if inch == 12:
        ft, inch = ft + 1, 0
    return f"{ft}'{inch}\""


def nbi_row(feature: dict[str, Any]) -> dict[str, Any] | None:
    props = feature.get("attributes", {}) or {}
    geom = feature.get("geometry") or {}
    lon, lat = geom.get("x"), geom.get("y")
    if lat is None or lon is None:
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None

    under = props.get("VERT_CLR_UND_054B") or 0
    under_ref = (props.get("VERT_CLR_UND_REF_054A") or "").strip().upper()
    over = props.get("VERT_CLR_OVER_MT_053") or 0
    candidates = []
    if under_ref == "H" and 0 < under < 4.9:
        candidates.append(float(under))
    if 0 < over < 4.9:
        candidates.append(float(over))
    if not candidates:
        return None
    clearance_m = min(candidates)

    structure = (props.get("STRUCTURE_NUMBER_008") or "").strip()
    state = (props.get("STATE_CODE_001") or "").strip()
    if not structure:
        return None
    ext_id = f"nbi-{state}-{structure}"

    facility = (props.get("FACILITY_CARRIED_007") or "").strip().strip("'")
    features_desc = (props.get("FEATURES_DESC_006A") or "").strip().strip("'")
    location = (props.get("LOCATION_009") or "").strip().strip("'")
    ftin = meters_to_ftin(clearance_m)
    name = f"Low bridge {ftin}"
    if facility:
        name += f" · {facility}"
    if features_desc:
        name += f" over {features_desc}"

    return {
        "osm_type": "external",
        "osm_id": external_osm_id("nbi", ext_id),
        "poi_type": "low_bridge",
        "name": name[:180],
        "brand": None,
        "operator": "FHWA NBI",
        "network": None,
        "lat": float(lat),
        "lon": float(lon),
        "country_code": "US",
        "tags": {
            "nbi": True,
            "clearance_m": round(clearance_m, 2),
            "clearance_ftin": ftin,
            "clearance_under_m": float(under) if under else None,
            "clearance_over_m": float(over) if over else None,
            "facility_carried": facility or None,
            "feature_under": features_desc or None,
            "location": location or None,
            "state_code": state or None,
        },
        "has_shower": False,
        "has_hgv_fuel": False,
        "has_weigh_station": False,
        "source": "nbi",
        "external_source": "nbi",
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
    with httpx.Client(timeout=120.0) as client:
        for i in range(0, len(rows), BATCH_SIZE):
            chunk = rows[i : i + BATCH_SIZE]
            resp = client.post(url, headers=headers, json=chunk)
            if resp.status_code >= 400:
                print(f"Upsert error {resp.status_code}: {resp.text[:400]}", file=sys.stderr)
                resp.raise_for_status()
            if (i // BATCH_SIZE) % 20 == 0:
                print(f"  upsert {i + len(chunk)}/{len(rows)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.dry_run and (not SUPABASE_URL or not SUPABASE_SERVICE_KEY):
        print("Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        sys.exit(1)

    print("Buscando pontes baixas do NBI (FHWA, < 4.9m/16ft)…")
    with httpx.Client() as client:
        features = fetch_low_bridges(client)

    rows: list[dict[str, Any]] = []
    for f in features:
        row = nbi_row(f)
        if row:
            rows.append(row)

    # Mesma lição do NTAD: a fonte pode ter chaves repetidas → dedup pela chave de conflito.
    unique: dict[tuple[str, str, str], dict[str, Any]] = {}
    for r in rows:
        unique[(r["external_source"], r["external_id"], r["poi_type"])] = r
    if len(unique) != len(rows):
        print(f"Deduped {len(rows)} → {len(unique)}")
    rows = list(unique.values())

    print(f"Total pontes baixas a inserir: {len(rows)}")
    if args.dry_run:
        import json as _json
        print(_json.dumps(rows[:2], indent=2))
        return

    upsert_batch(rows)
    print("Done.")


if __name__ == "__main__":
    main()
