#!/usr/bin/env bash
# Copia government-poi-ingest para EC2 via EC2 Instance Connect (chave válida ~60s).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KEY="${HOME}/.ssh/truckereasy-valhalla.pem"
REGION="${AWS_REGION:-us-west-2}"
INSTANCE_ID="${INSTANCE_ID:-}"
IP="${VALHALLA_IP:-}"

state=$(ls -t "${HOME}"/valhalla-oregon-i-*.env 2>/dev/null | head -1 || true)
if [[ -n "$state" && -f "$state" ]]; then
  # shellcheck source=/dev/null
  source "$state"
fi

if [[ -z "$INSTANCE_ID" || -z "$IP" ]]; then
  echo "source ~/valhalla-oregon-i-*.env primeiro"
  exit 1
fi

if [[ ! -f "$KEY" || ! -f "${KEY}.pub" ]]; then
  echo "Chave em falta: ${KEY} — corre mac-ssh-instancia.sh uma vez"
  exit 1
fi

AZ=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

echo "A autorizar chave SSH na instância ${INSTANCE_ID} (${IP})..."
aws ec2-instance-connect send-ssh-public-key \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --availability-zone "$AZ" \
  --instance-os-user ubuntu \
  --ssh-public-key "file://${KEY}.pub"

echo "A copiar government-poi-ingest (janela ~60s)..."
rsync -az \
  -e "ssh -i ${KEY} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15" \
  "${REPO_ROOT}/backend/government-poi-ingest/" \
  "ubuntu@${IP}:/home/ubuntu/government-poi-ingest/"

echo ""
echo "✅ Copiado para ubuntu@${IP}:/home/ubuntu/government-poi-ingest/"
echo ""
echo "Na EC2:"
echo "  cd ~/government-poi-ingest && python3 -m venv .venv && source .venv/bin/activate"
echo "  pip install -r requirements.txt"
echo "  cp .env.example .env   # SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY"
echo "  python3 sync_public_truck_feeds.py"
echo "  python3 sync_operational_feeds.py"
