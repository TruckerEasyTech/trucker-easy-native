#!/usr/bin/env bash
# Run ON the EC2 instance (SSM shell), inside the folder that contains Dockerfile + app/.
# Dockerfile listens on 8787 inside the container; host maps 8003 (matches Supabase secret).
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f Dockerfile ]]; then
  echo "ERROR: run from backend/quantum-routing (Dockerfile missing)."
  exit 1
fi

sudo docker build -t quantum-routing .
sudo docker rm -f quantum-routing 2>/dev/null || true
sudo docker run -d \
  --name quantum-routing \
  --restart unless-stopped \
  -e ROUTE_OPT_SOLVER=greedy \
  -e DISABLE_DWAVE=1 \
  -e USE_AMAZON_BRAKET=0 \
  -p 8003:8787 \
  quantum-routing

sleep 4
curl -s "http://127.0.0.1:8003/health" || true
echo ""
echo "If health OK, route-proxy upstream should stop returning 502."
