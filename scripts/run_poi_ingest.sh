#!/usr/bin/env bash
# Atualiza poi_places no Supabase via Overpass (US+CA).
# Uso: ./scripts/run_poi_ingest.sh [--dry-run] [--region us-tx]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INGEST="${ROOT}/backend/osm-poi-ingest"
LOG_DIR="${ROOT}/backend/osm-poi-ingest/logs"
mkdir -p "$LOG_DIR"

if [[ ! -f "${INGEST}/.env" ]]; then
  echo "Crie ${INGEST}/.env a partir de .env.example (SUPABASE_URL + SERVICE_ROLE_KEY)."
  exit 1
fi

cd "$INGEST"
python3 -m pip install -q -r requirements.txt

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="${LOG_DIR}/ingest_${STAMP}.log"

echo "POI ingest started $(date -Iseconds)" | tee "$LOG"

if [[ "${1:-}" == "--dry-run" ]]; then
  python3 ingest_overpass.py --region us-tx-dfw --dry-run 2>&1 | tee -a "$LOG"
elif [[ "${1:-}" == "--region" && -n "${2:-}" ]]; then
  python3 ingest_overpass.py --region "$2" 2>&1 | tee -a "$LOG"
else
  python3 ingest_overpass.py --all 2>&1 | tee -a "$LOG"
fi

echo "POI ingest finished $(date -Iseconds)" | tee -a "$LOG"
echo "Log: $LOG"
