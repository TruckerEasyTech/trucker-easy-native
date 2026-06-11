#!/usr/bin/env bash
# Deploy public POI ops-feed (Road511 OFF by default).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_REF="${SUPABASE_PROJECT_REF:-usowafvqawbunyhmfscx}"

cd "$ROOT"

echo "→ Applying government POI SQL (idempotent)"
supabase db query -f "supabase/sql/apply_government_poi_operational_remote.sql" \
  --linked --workdir "$ROOT" --agent no 2>/dev/null || true

echo "→ Deploying ops-feed + trucking-poi-feed (Road511 via ROAD511_API_KEY in Edge secrets)"
for fn in ops-feed trucking-poi-feed; do
  supabase functions deploy "$fn" \
    --project-ref "$PROJECT_REF" \
    --workdir "$ROOT" \
    --use-api \
    --yes
done

echo ""
echo "Cron on EC2: bash scripts/run_government_poi_sync.sh  (gov + Road511 partner sync)"
echo "Set ROAD511_API_KEY in Supabase → Edge Functions → Secrets"
echo "Docs: docs/POI_OPERATIONS.md · docs/POI_FREE_PUBLIC_FEEDS.md"
