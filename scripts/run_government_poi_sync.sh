#!/usr/bin/env bash
# Sync official truck POI + weigh/parking signals into Supabase (US/CA, $0 feeds).
# Run on EC2 via cron every 10 minutes — see docs/POI_FREE_PUBLIC_FEEDS.md
#
# Cron (ubuntu user — log in home, not /var/log):
#   */10 * * * * /home/ubuntu/trucker-easy-app/scripts/run_government_poi_sync.sh >> /home/ubuntu/logs/truckereasy-gov-poi.log 2>&1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INGEST="${ROOT}/backend/government-poi-ingest"

# Allow override: LOG_FILE=/path/to.log ./run_government_poi_sync.sh
if [[ -n "${LOG_FILE:-}" ]]; then
  mkdir -p "$(dirname "${LOG_FILE}")"
  exec >>"${LOG_FILE}" 2>&1
fi

if [[ -f "${INGEST}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${INGEST}/.env"
  set +a
elif [[ -f "${HOME}/government-poi-ingest/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${HOME}/government-poi-ingest/.env"
  set +a
fi

: "${SUPABASE_URL:?Set SUPABASE_URL in backend/government-poi-ingest/.env or ~/government-poi-ingest/.env}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Set SUPABASE_SERVICE_ROLE_KEY}"

SYNC_DIR="${INGEST}"
[[ -d "${SYNC_DIR}" ]] || SYNC_DIR="${HOME}/government-poi-ingest"

cd "${SYNC_DIR}"
if [[ -d "${SYNC_DIR}/.venv" ]]; then
  # shellcheck disable=SC1091
  source "${SYNC_DIR}/.venv/bin/activate"
fi

python3 sync_public_truck_feeds.py
python3 sync_operational_feeds.py

# Road511 / partner live open-closed (requires ROAD511_API_KEY in Supabase Edge secrets).
if [[ -f "${SYNC_DIR}/sync_partner_feeds.py" ]]; then
  python3 sync_partner_feeds.py || echo "[warn] sync_partner_feeds failed (check ROAD511_API_KEY in Supabase secrets)"
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] government POI sync OK"
