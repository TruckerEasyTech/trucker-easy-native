#!/usr/bin/env bash
# Nationwide weigh baseline: USDOT NTAD WIM (all 50 states) + OSM from Valhalla PBF.
# Run after deploy or weekly (also called from run_weekly_poi.sh).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
GOV="${DIR}/gov"

if [[ -f "${DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${DIR}/.env"
  set +a
fi

: "${SUPABASE_URL:?SUPABASE_URL missing}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY missing}"

if [[ -d "${DIR}/.venv" ]]; then
  # shellcheck disable=SC1091
  source "${DIR}/.venv/bin/activate"
fi

echo "▶ ingest_ntad.py (USDOT WIM — all US states, public domain)…"
python3 "${GOV}/ingest_ntad.py"

PBF="${VALHALLA_PBF:-/opt/valhalla/custom_files/us-canada.osm.pbf}"
if [[ -f "${PBF}" ]]; then
  echo "▶ ingest_osmium.py (${PBF}) — OSM weigh_station + truck POIs US+CA…"
  python3 "${DIR}/ingest_osmium.py" "${PBF}"
else
  echo "⚠ No PBF at ${PBF} — skip OSM osmium ingest"
fi

echo "✅ National weigh baseline OK — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
