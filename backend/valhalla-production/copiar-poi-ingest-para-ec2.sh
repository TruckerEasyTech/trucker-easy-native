#!/usr/bin/env bash
# Copia o ingest de POIs para a EC2 Valhalla.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KEY="${KEY_NAME:-truckereasy-valhalla}"
PEM="${HOME}/.ssh/${KEY}.pem"
IP="${VALHALLA_IP:-}"

if [[ -z "$IP" ]]; then
  state=$(ls -t "${HOME}"/valhalla-oregon-i-*.env 2>/dev/null | head -1 || true)
  if [[ -n "$state" && -f "$state" ]]; then
    # shellcheck source=/dev/null
    source "$state"
    IP="${VALHALLA_IP:-}"
  fi
fi

if [[ -z "$IP" ]]; then
  echo "Define o IP: export VALHALLA_IP=54.x.x.x"
  echo "Ou: source ~/valhalla-oregon-i-XXXX.env"
  exit 1
fi

if [[ ! -f "$PEM" ]]; then
  echo "Chave SSH não encontrada: $PEM"
  exit 1
fi

echo "Copiando backend/osm-poi-ingest para ubuntu@${IP}:/home/ubuntu/osm-poi-ingest ..."
rsync -az --delete \
  -e "ssh -i ${PEM} -o StrictHostKeyChecking=accept-new" \
  "${REPO_ROOT}/backend/osm-poi-ingest/" \
  "ubuntu@${IP}:/home/ubuntu/osm-poi-ingest/"

echo "Copiando backend/government-poi-ingest para ubuntu@${IP}:/home/ubuntu/government-poi-ingest ..."
rsync -az --delete \
  -e "ssh -i ${PEM} -o StrictHostKeyChecking=accept-new" \
  "${REPO_ROOT}/backend/government-poi-ingest/" \
  "ubuntu@${IP}:/home/ubuntu/government-poi-ingest/"

echo ""
echo "Copiado. Agora entre na EC2:"
echo "  ssh -i ${PEM} ubuntu@${IP}"
echo ""
echo "OSM ingest:"
echo "  cd /home/ubuntu/osm-poi-ingest"
echo "  sudo apt-get update && sudo apt-get install -y osmium-tool python3-venv"
echo "  python3 -m venv .venv"
echo "  . .venv/bin/activate"
echo "  pip install -r requirements.txt"
echo "  export SUPABASE_URL=\"https://usowafvqawbunyhmfscx.supabase.co\""
echo "  export SUPABASE_SERVICE_ROLE_KEY=\"COLE_A_SERVICE_ROLE_KEY_AQUI\""
echo "  python3 ingest_osmium.py --dry-run"
echo ""
echo "Gov feeds (balança open/closed oficial):"
echo "  cd /home/ubuntu/government-poi-ingest"
echo "  python3 -m venv .venv"
echo "  . .venv/bin/activate"
echo "  pip install -r requirements.txt"
echo "  cp .env.example .env   # preencher SUPABASE_URL + SERVICE_ROLE_KEY"
echo "  python3 sync_public_truck_feeds.py"
echo "  python3 sync_operational_feeds.py"
