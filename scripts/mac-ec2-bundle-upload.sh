#!/usr/bin/env bash
# Mac: empacota quantum-routing + osm-poi-ingest (sem .venv) e sobe para S3.
# Use quando SSH/SCP falhar (ex.: sessão só via SSM). Depois cole o bloco EC2 que o script imprime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="/tmp/truckereasy-ec2-bundle.tgz"
BUCKET="${EC2_DEPLOY_BUCKET:-amazon-braket-truckereasy-7mountains}"
KEY="deploy/truckereasy-ec2-bundle-$(date +%Y%m%d_%H%M%S).tgz"
REGION="${AWS_REGION:-us-west-2}"

tar -czf "$BUNDLE" \
  --exclude='.venv' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='.env' \
  -C "$ROOT/backend" \
  quantum-routing osm-poi-ingest

echo "Upload $(du -h "$BUNDLE" | awk '{print $1}') → s3://${BUCKET}/${KEY}"
aws s3 cp "$BUNDLE" "s3://${BUCKET}/${KEY}" --region "$REGION"
URL=$(aws s3 presign "s3://${BUCKET}/${KEY}" --expires-in 86400 --region "$REGION")

cat <<EOF

✅ Bundle no S3 (link válido ~24h):

${URL}

--- Cole isto na EC2 (SSM / SSH) ---

cd ~
curl -fsSL -o truckereasy-ec2-bundle.tgz '${URL}'
tar -xzf truckereasy-ec2-bundle.tgz
rm -f truckereasy-ec2-bundle.tgz
cd ~/quantum-routing && bash deploy-ec2-docker.sh
curl -s http://127.0.0.1:8003/health
echo ""
echo "POI ingest:"
echo "  cd ~/osm-poi-ingest && cp .env.example .env && nano .env"

EOF
