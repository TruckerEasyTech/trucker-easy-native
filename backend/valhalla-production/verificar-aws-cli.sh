#!/usr/bin/env bash
# Verifica se o Mac está pronto para criar a EC2 Valhalla.
set -euo pipefail

echo "=== Trucker Easy — verificação AWS CLI ==="
echo ""

ok=true

if ! command -v aws &>/dev/null; then
  echo "❌ AWS CLI não instalado. Corre: brew install awscli"
  ok=false
else
  echo "✅ aws $(aws --version 2>&1 | head -1)"
fi

if $ok; then
  if aws sts get-caller-identity --output json 2>/dev/null; then
    echo ""
    echo "✅ Credenciais OK"
  else
    echo "❌ Credenciais inválidas. Corre: aws configure  (região us-west-2)"
    ok=false
  fi
fi

region="${AWS_REGION:-us-west-2}"
if $ok && aws ec2 describe-regions --region-names "$region" --query 'Regions[0].RegionName' --output text 2>/dev/null | grep -q "$region"; then
  echo "✅ Região $region acessível"
else
  echo "⚠️  Confirma região us-west-2 em aws configure"
fi

key="${KEY_NAME:-truckereasy-valhalla}"
if aws ec2 describe-key-pairs --key-names "$key" --region "$region" &>/dev/null; then
  echo "✅ Key pair '$key' existe em $region"
else
  echo "⚠️  Key pair '$key' ainda não existe. Cria com:"
  echo "    aws ec2 create-key-pair --key-name $key --region $region --query KeyMaterial --output text > ~/.ssh/${key}.pem"
  echo "    chmod 400 ~/.ssh/${key}.pem"
fi

echo ""
if $ok; then
  echo "Próximo passo:"
  echo "  export VALHALLA_DOMAIN=valhalla.truckereasy.com"
  echo "  bash run-bootstrap-from-mac.sh"
else
  exit 1
fi
