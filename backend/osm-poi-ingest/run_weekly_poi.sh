#!/usr/bin/env bash
# Weekly POI refresh: OSM (osmium PBF or Overpass corridors) + USDOT NTAD.
# EC2 cron: 0 4 * * 0  (Domingo 04:00 UTC)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${HOME}/logs"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/poi-weekly-$(date +%Y%m%d).log"
exec >>"${LOG}" 2>&1

echo "=== Weekly POI ingest $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

if [[ -f "${DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${DIR}/.env"
  set +a
fi

: "${SUPABASE_URL:?SUPABASE_URL missing in ${DIR}/.env}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY missing}"

if [[ -d "${DIR}/.venv" ]]; then
  # shellcheck disable=SC1091
  source "${DIR}/.venv/bin/activate"
fi

pip install -q -r "${DIR}/requirements.txt" 2>/dev/null || pip install -q httpx python-dotenv

PBF="${VALHALLA_PBF:-/opt/valhalla/custom_files/us-canada.osm.pbf}"
if [[ -f "${PBF}" ]]; then
  echo "▶ ingest_osmium.py (${PBF})"
  python3 "${DIR}/ingest_osmium.py" "${PBF}"
else
  echo "▶ No Valhalla PBF — Overpass corridor tiles"
  REGIONS=(
    ca-on us-tx-dfw us-tx-houston us-il-chicago
    us-oh-turnpike us-pa-i80-east us-ca
  )
  for r in "${REGIONS[@]}"; do
    echo "  region ${r}…"
    python3 "${DIR}/ingest_overpass.py" --region "${r}" || echo "  warn: ${r} failed"
    sleep 25
  done
fi

echo "▶ ingest_ntad.py (USDOT WIM all states)…"
python3 "${GOV}/ingest_ntad.py"

echo "✅ Weekly POI done $(date -u +%Y-%m-%dT%H:%M:%SZ)"
