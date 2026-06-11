#!/usr/bin/env bash
# Copia backend/quantum-routing do Mac para a EC2 (requer SSH porta 22 aberta no Security Group).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KEY="${KEY_NAME:-truckereasy-valhalla}"
PEM="${HOME}/.ssh/${KEY}.pem"
IP="${VALHALLA_IP:-34.221.235.246}"
USER="${EC2_USER:-ubuntu}"
REMOTE_DIR="${REMOTE_DIR:-/home/ubuntu/quantum-routing}"

if [[ ! -f "$PEM" ]]; then
  echo "Chave SSH não encontrada: $PEM"
  echo "Ou: export KEY_NAME=sua-chave"
  exit 1
fi

if [[ ! -d "$ROOT/backend/quantum-routing" ]]; then
  echo "Pasta não encontrada: $ROOT/backend/quantum-routing"
  exit 1
fi

echo "Copiando quantum-routing para ${USER}@${IP}:${REMOTE_DIR} ..."
rsync -az --delete \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  --exclude '.env' \
  -e "ssh -i ${PEM} -o StrictHostKeyChecking=accept-new" \
  "$ROOT/backend/quantum-routing/" \
  "${USER}@${IP}:${REMOTE_DIR}/"

echo ""
echo "✅ Copiado. No EC2 (SSH ou SSM):"
echo "  cd ${REMOTE_DIR}"
echo "  bash deploy-ec2-docker.sh"
echo "  curl -s http://127.0.0.1:8003/health"
