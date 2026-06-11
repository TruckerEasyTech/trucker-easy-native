#!/usr/bin/env bash
# Copia deploy.sh do Mac para a EC2 (antes do SSH).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${KEY_NAME:-truckereasy-valhalla}"
PEM="${HOME}/.ssh/${KEY}.pem"
IP="${VALHALLA_IP:-}"

if [[ -z "$IP" ]]; then
  # tentar carregar do último state file
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

echo "Copiando deploy.sh para ubuntu@${IP}:/tmp/deploy.sh ..."
scp -i "$PEM" -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/deploy.sh" \
  "ubuntu@${IP}:/tmp/deploy.sh"

echo ""
echo "✅ Copiado. Agora:"
echo "  ssh -i $PEM ubuntu@${IP}"
echo "  sudo bash /tmp/deploy.sh valhalla.truckereasy.com"
