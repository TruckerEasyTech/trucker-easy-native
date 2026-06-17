#!/usr/bin/env python3
"""
Sync state 511 traffic cameras into public.traffic_cameras (Supabase).

Dado REAL e gratuito: cada DOT estadual publica suas câmeras via API 511 (chave de dev grátis).
A LOCALIZAÇÃO da câmera vai pro Supabase; a IMAGEM é uma URL ao vivo do DOT (refresca ao abrir).

Roda no cron (ex.: a cada 30-60 min — as câmeras mudam de local raramente). Só busca os estados
que tiverem a chave configurada via env — nada é fabricado; estado sem chave é simplesmente pulado.

Dois formatos suportados:
  - "standard"   = API 511 GetCameras (511NY, 511GA, 511WI, FL511 ...): ?key=KEY&format=json
  - "castlerock" = API Castle Rock v2 (AZ511, NV nvroads ...): /api/v2/get/cameras?key=KEY&format=json

Config: cada feed lê a chave de uma env var própria (NY511_KEY, GA511_KEY, ...). Adicionar um
estado = registrar a chave grátis + setar a env. Sem chave => pulado (log claro).

Uso:
  python sync_traffic_cameras.py --dry-run
  python sync_traffic_cameras.py
"""
from __future__ import annotations

import argparse
import os
import sys
from typing import Any

import httpx

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Cada feed: source (estável), URL base, env da chave grátis, e o formato da API.
# Adicionar estado = só registrar a chave grátis no portal 511 dele e setar a env var.
CAMERA_FEEDS: list[dict[str, str]] = [
    {"source": "511ny", "url": "https://511ny.org/api/GetCameras",       "key_env": "NY511_KEY", "kind": "standard"},
    {"source": "511ga", "url": "https://511ga.org/api/GetCameras",       "key_env": "GA511_KEY", "kind": "standard"},
    {"source": "511wi", "url": "https://511wi.gov/api/GetCameras",       "key_env": "WI511_KEY", "kind": "standard"},
    {"source": "fl511", "url": "https://fl511.com/api/GetCameras",       "key_env": "FL511_KEY", "kind": "standard"},
    {"source": "az511", "url": "https://az511.com/api/v2/get/cameras",   "key_env": "AZ511_KEY", "kind": "castlerock"},
    {"source": "nv511", "url": "https://www.nvroads.com/api/v2/get/cameras", "key_env": "NV511_KEY", "kind": "castlerock"},
]


def _first(d: dict[str, Any], *keys: str) -> Any:
    """Primeiro valor não-nulo entre nomes de campo possíveis (APIs variam o casing/nome)."""
    for k in keys:
        if k in d and d[k] not in (None, ""):
            return d[k]
    return None


def _to_float(v: Any) -> float | None:
    try:
        f = float(v)
        return f if f == f else None  # descarta NaN
    except (TypeError, ValueError):
        return None


def _truthy_disabled(v: Any) -> bool:
    if v is None:
        return False
    s = str(v).strip().lower()
    return s in ("1", "true", "yes", "disabled", "blocked", "offline")


def normalize_standard(cam: dict[str, Any], source: str) -> dict[str, Any] | None:
    """API 511 GetCameras (NY/GA/WI/FL)."""
    lat = _to_float(_first(cam, "Latitude", "latitude", "Lat"))
    lon = _to_float(_first(cam, "Longitude", "longitude", "Lon", "Lng"))
    image = _first(cam, "Url", "URL", "ImageUrl", "imageUrl")
    if lat is None or lon is None or not image:
        return None
    ext_id = _first(cam, "ID", "Id", "id", "CameraId")
    if ext_id is None:
        return None
    disabled = _truthy_disabled(_first(cam, "DisabledFlag", "Disabled")) or _truthy_disabled(_first(cam, "BlockedFlag", "Blocked"))
    return {
        "source": source,
        "external_id": str(ext_id),
        "name": _first(cam, "Name", "Description", "name"),
        "roadway": _first(cam, "RoadwayName", "Roadway", "roadway"),
        "direction": _first(cam, "DirectionOfTravel", "Direction", "direction"),
        "latitude": lat,
        "longitude": lon,
        "image_url": str(image),
        "video_url": _first(cam, "VideoUrl", "videoUrl"),
        "disabled": disabled,
    }


def normalize_castlerock(cam: dict[str, Any], source: str) -> dict[str, Any] | None:
    """API Castle Rock v2/get/cameras (AZ/NV): imagem dentro de 'views'."""
    lat = _to_float(_first(cam, "latitude", "Latitude"))
    lon = _to_float(_first(cam, "longitude", "Longitude"))
    ext_id = _first(cam, "id", "Id", "sourceId", "ID")
    if lat is None or lon is None or ext_id is None:
        return None
    views = cam.get("views") or cam.get("Views") or []
    image = None
    video = None
    for v in views if isinstance(views, list) else []:
        u = _first(v, "url", "Url")
        if not u:
            continue
        if str(u).lower().endswith((".m3u8", ".mp4")) or "video" in str(u).lower():
            video = video or str(u)
        else:
            image = image or str(u)
    if not image:
        return None
    return {
        "source": source,
        "external_id": str(ext_id),
        "name": _first(cam, "name", "Name", "description"),
        "roadway": _first(cam, "roadway", "Roadway"),
        "direction": _first(cam, "direction", "Direction"),
        "latitude": lat,
        "longitude": lon,
        "image_url": image,
        "video_url": video,
        "disabled": False,
    }


def fetch_feed(client: httpx.Client, feed: dict[str, str], key: str) -> list[dict[str, Any]]:
    params = {"key": key, "format": "json"}
    resp = client.get(feed["url"], params=params, timeout=60.0)
    if resp.status_code >= 400:
        print(f"[{feed['source']}] HTTP {resp.status_code}: {resp.text[:200]}", file=sys.stderr)
        return []
    try:
        data = resp.json()
    except Exception as e:  # noqa: BLE001
        print(f"[{feed['source']}] JSON inválido: {e}", file=sys.stderr)
        return []
    # APIs retornam lista direta OU {"Cameras":[...]} / {"cameras":[...]}
    if isinstance(data, dict):
        data = data.get("Cameras") or data.get("cameras") or data.get("data") or []
    rows: list[dict[str, Any]] = []
    norm = normalize_standard if feed["kind"] == "standard" else normalize_castlerock
    for cam in data if isinstance(data, list) else []:
        if not isinstance(cam, dict):
            continue
        r = norm(cam, feed["source"])
        if r:
            rows.append(r)
    return rows


def upsert_cameras(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        # merge-duplicates: re-rodar ATUALIZA (não duplica) — chave única (source, external_id).
        "Prefer": "return=minimal,resolution=merge-duplicates",
    }
    url = f"{SUPABASE_URL}/rest/v1/traffic_cameras?on_conflict=source,external_id"
    with httpx.Client(timeout=60.0) as client:
        batch = 200
        for i in range(0, len(rows), batch):
            chunk = rows[i : i + batch]
            resp = client.post(url, headers=headers, json=chunk)
            if resp.status_code >= 400:
                print(f"Upsert error {resp.status_code}: {resp.text[:500]}", file=sys.stderr)
                resp.raise_for_status()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.dry_run and (not SUPABASE_URL or not SUPABASE_SERVICE_KEY):
        print("SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios", file=sys.stderr)
        sys.exit(1)

    all_rows: list[dict[str, Any]] = []
    with httpx.Client() as client:
        for feed in CAMERA_FEEDS:
            key = os.environ.get(feed["key_env"], "").strip()
            if not key:
                print(f"[{feed['source']}] pulado — sem {feed['key_env']} (registre a chave grátis no portal 511)")
                continue
            rows = fetch_feed(client, feed, key)
            print(f"[{feed['source']}] {len(rows)} câmeras")
            all_rows.extend(rows)

    if not all_rows:
        print("Nenhuma câmera (nenhuma chave 511 configurada). Nada a fazer — sem dado fabricado.")
        return

    print(f"Total: {len(all_rows)} câmeras de {len({r['source'] for r in all_rows})} feeds.")
    if args.dry_run:
        for r in all_rows[:5]:
            print("  ", r["source"], r["roadway"], r["latitude"], r["longitude"], r["image_url"][:60])
        print("(dry-run — nada gravado)")
        return

    upsert_cameras(all_rows)
    print(f"OK — {len(all_rows)} câmeras upsertadas em traffic_cameras.")


if __name__ == "__main__":
    main()
