#!/usr/bin/env bash
# Deploy route-proxy Edge Function (HTTPS gateway for route optimization).
# Run from Mac Terminal after: supabase login --token 'sbp_...'
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_REF="${SUPABASE_PROJECT_REF:-usowafvqawbunyhmfscx}"
UPSTREAM_URL="${ROUTE_OPTIMIZATION_UPSTREAM_URL:-http://34.221.235.246:8003}"

cd "$ROOT"

echo "→ Setting secret ROUTE_OPTIMIZATION_UPSTREAM_URL"
supabase secrets set \
  "ROUTE_OPTIMIZATION_UPSTREAM_URL=${UPSTREAM_URL}" \
  --project-ref "$PROJECT_REF" \
  --workdir "$ROOT"

echo "→ Deploying route-proxy"
supabase functions deploy route-proxy \
  --project-ref "$PROJECT_REF" \
  --workdir "$ROOT" \
  --yes

echo ""
echo "Done. Test (expect 401 without real user JWT):"
echo "  curl -s -X POST \"https://${PROJECT_REF}.supabase.co/functions/v1/route-proxy/v1/optimize\" \\"
echo "    -H \"apikey: \$SUPABASE_ANON_KEY\" -H \"Authorization: Bearer \$SUPABASE_ANON_KEY\" \\"
echo "    -H \"Content-Type: application/json\" -d '{\"stops\":[]}'"
