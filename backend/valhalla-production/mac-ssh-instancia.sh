#!/usr/bin/env bash
# SSH/SCP na EC2 sem o .pem original — usa EC2 Instance Connect (chave temporária 60s).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-west-2}"
KEY_PATH="${HOME}/.ssh/truckereasy-valhalla.pem"
INSTANCE_ID="${INSTANCE_ID:-}"
IP="${VALHALLA_IP:-}"

state=$(ls -t "${HOME}"/valhalla-oregon-i-*.env 2>/dev/null | head -1 || true)
if [[ -n "$state" && -f "$state" ]]; then
  # shellcheck source=/dev/null
  source "$state"
  INSTANCE_ID="${INSTANCE_ID:-}"
  IP="${VALHALLA_IP:-}"
fi

if [[ -z "$INSTANCE_ID" ]]; then
  echo "INSTANCE_ID em falta. source ~/valhalla-oregon-i-*.env"
  exit 1
fi

AZ=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

if [[ ! -f "${KEY_PATH}" ]]; then
  echo "A criar chave local ${KEY_PATH} (só para Instance Connect)..."
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "truckereasy-mac"
  chmod 400 "$KEY_PATH"
fi

echo "A enviar chave pública para a instância (${INSTANCE_ID}, ${AZ})..."
aws ec2-instance-connect send-ssh-public-key \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --availability-zone "$AZ" \
  --instance-os-user ubuntu \
  --ssh-public-key "file://${KEY_PATH}.pub"

echo ""
echo "✅ Janela ~60s. Corre AGORA noutra linha ou continua:"
echo "  scp -i ${KEY_PATH} ${SCRIPT_DIR}/deploy.sh ubuntu@${IP}:/tmp/deploy.sh"
echo "  ssh -i ${KEY_PATH} ubuntu@${IP}"
echo ""
if [[ "${1:-}" == "scp" ]]; then
  scp -i "$KEY_PATH" -o StrictHostKeyChecking=accept-new \
    "${SCRIPT_DIR}/deploy.sh" "ubuntu@${IP}:/tmp/deploy.sh"
  echo "✅ deploy.sh copiado."
elif [[ "${1:-}" == "ssh" ]]; then
  exec ssh -i "$KEY_PATH" -o StrictHostKeyChecking=accept-new "ubuntu@${IP}"
fi
