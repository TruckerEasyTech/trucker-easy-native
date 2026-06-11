#!/usr/bin/env bash
# Pull Road511 weigh + parking into Supabase via trucking-poi-feed (persist=1).
# Keys live in Supabase Edge secrets (ROAD511_API_KEY + ENABLE_ROAD511=true) — not in this script.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INGEST="${ROOT}/backend/government-poi-ingest"

if [[ -f "${INGEST}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${INGEST}/.env"
  set +a
fi

: "${SUPABASE_URL:?Set SUPABASE_URL in backend/government-poi-ingest/.env}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY (Dashboard → API → anon JWT)}"

cd "${INGEST}"
if [[ -d .venv ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

python3 sync_partner_feeds.py
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Road511 corridor sync OK"
