#!/usr/bin/env bash
# Cria EC2 Valhalla em Oregon a partir do Mac (alternativa ao CloudShell).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export AWS_REGION="${AWS_REGION:-us-west-2}"
export KEY_NAME="${KEY_NAME:-truckereasy-valhalla}"
export VALHALLA_DOMAIN="${VALHALLA_DOMAIN:-valhalla.truckereasy.com}"

if ! command -v aws &>/dev/null; then
  echo "Instala AWS CLI: brew install awscli"
  echo "Depois: aws configure  (região us-west-2)"
  exit 1
fi

echo "Verificando credenciais AWS..."
aws sts get-caller-identity --region "$AWS_REGION" >/dev/null

echo "Região: $AWS_REGION"
echo "Domínio: $VALHALLA_DOMAIN"
echo "Key pair: $KEY_NAME"
echo ""

bash "$SCRIPT_DIR/aws-oregon-valhalla-bootstrap.sh"
