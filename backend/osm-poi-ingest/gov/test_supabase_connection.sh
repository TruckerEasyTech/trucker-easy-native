#!/usr/bin/env bash
# Test Supabase REST + service role from EC2 (run from ~/osm-poi-ingest after sourcing .env)
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${DIR}/.env"
  set +a
fi

: "${SUPABASE_URL:?missing SUPABASE_URL}"
: "${SUPABASE_SERVICE_ROLE_KEY:?missing SUPABASE_SERVICE_ROLE_KEY}"

echo "GET poi_places count (gov sources)…"
code=$(curl -sS -o /tmp/sb-test.json -w "%{http_code}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Prefer: count=exact" \
  -I "${SUPABASE_URL}/rest/v1/poi_places?external_source=eq.on511&select=id&limit=1")

echo "HTTP ${code}"
grep -i content-range /tmp/sb-test.json 2>/dev/null || head -5 /tmp/sb-test.json

if [[ "${code}" != "200" && "${code}" != "206" ]]; then
  echo "❌ Auth or URL problem — check SERVICE_ROLE_KEY in .env"
  exit 1
fi
echo "✅ Supabase REST OK"
