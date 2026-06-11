#!/usr/bin/env bash
# Gov feeds (Ontario 511, Caltrans, OHGO) — run from ~/osm-poi-ingest on EC2.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
GOV="${DIR}/gov"

if [[ ! -f "${GOV}/sync_public_truck_feeds.py" ]]; then
  echo "❌ Falta ${GOV}/sync_public_truck_feeds.py"
  echo "   Copia de novo do Mac: backend/osm-poi-ingest/ (pasta gov/ incluída)"
  exit 1
fi

if [[ -f "${DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${DIR}/.env"
  set +a
elif [[ -f "${GOV}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${GOV}/.env"
  set +a
fi

: "${SUPABASE_URL:?Define SUPABASE_URL in ~/osm-poi-ingest/.env}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Define SUPABASE_SERVICE_ROLE_KEY in ~/osm-poi-ingest/.env}"

if [[ -d "${DIR}/.venv" ]]; then
  # shellcheck disable=SC1091
  source "${DIR}/.venv/bin/activate"
fi

cd "${GOV}"
echo "▶ sync_public_truck_feeds.py (Ontario 511 + BC CVSE + Caltrans)…"
python3 sync_public_truck_feeds.py
echo "▶ sync_operational_feeds.py (OHGO + TPIMS)…"
python3 sync_operational_feeds.py
echo "✅ Gov sync OK — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
