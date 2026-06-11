#!/usr/bin/env bash
# ============================================================
# Trucker Easy — AWS Oregon (us-west-2) Valhalla bootstrap
#
# Run in: AWS CloudShell (region = us-west-2 / Oregon)
# Creates: EC2 c5.xlarge + 160GB + Security Group + Elastic IP
# Does NOT install Valhalla tiles (run deploy.sh on the EC2 via SSH).
#
# Usage (CloudShell):
#   export VALHALLA_DOMAIN=valhalla.truckereasy.com
#   export KEY_NAME=truckereasy-valhalla
#   bash aws-oregon-valhalla-bootstrap.sh
#
# Optional env:
#   AWS_REGION=us-west-2          (default)
#   INSTANCE_TYPE=c5.xlarge       (default)
#   VOLUME_GB=160                 (default)
#   KEY_NAME=...                  (required — must exist in us-west-2)
#   VALHALLA_DOMAIN=...          (required for DNS instructions)
#   SSH_CIDR=0.0.0.0/0            (restrict to your IP in production)
# ============================================================

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-west-2}"
INSTANCE_TYPE="${INSTANCE_TYPE:-c5.xlarge}"
VOLUME_GB="${VOLUME_GB:-160}"
SSH_CIDR="${SSH_CIDR:-0.0.0.0/0}"
SG_NAME="${SG_NAME:-valhalla-truck-oregon}"
INSTANCE_NAME="${INSTANCE_NAME:-valhalla-truck-oregon}"

if [[ -z "${KEY_NAME:-}" ]]; then
  echo "ERROR: export KEY_NAME=your-key-pair-name  (EC2 Key Pair in us-west-2)"
  exit 1
fi

if [[ -z "${VALHALLA_DOMAIN:-}" ]]; then
  echo "ERROR: export VALHALLA_DOMAIN=valhalla.truckereasy.com"
  exit 1
fi

echo "=== Trucker Easy — Valhalla AWS Bootstrap (Oregon) ==="
echo "Region:    $AWS_REGION"
echo "Domain:    $VALHALLA_DOMAIN"
echo "Key:       $KEY_NAME"
echo "Instance:  $INSTANCE_TYPE (${VOLUME_GB}GB gp3)"
echo ""

# --- Latest Ubuntu 24.04 Noble (Canonical) ---
echo "[1/6] Resolving Ubuntu 24.04 AMI in $AWS_REGION..."
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --region "$AWS_REGION" \
  --filters \
    "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
    "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
  echo "ERROR: Could not find Ubuntu 24.04 AMI. Check region $AWS_REGION."
  exit 1
fi
echo "       AMI: $AMI_ID"

# --- Key pair exists ---
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "ERROR: Key pair '$KEY_NAME' not found in $AWS_REGION."
  echo "Create one: EC2 → Key pairs → Create, or:"
  echo "  aws ec2 create-key-pair --key-name $KEY_NAME --region $AWS_REGION --query KeyMaterial --output text > ~/${KEY_NAME}.pem"
  exit 1
fi

# --- Default VPC ---
echo "[2/6] Default VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --region "$AWS_REGION" \
  --query 'Vpcs[0].VpcId' \
  --output text)

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "ERROR: No default VPC in $AWS_REGION."
  exit 1
fi
echo "       VPC: $VPC_ID"

# --- Security group ---
echo "[3/6] Security group ($SG_NAME)..."
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Valhalla truck routing (Trucker Easy)" \
    --vpc-id "$VPC_ID" \
    --region "$AWS_REGION" \
    --query GroupId \
    --output text)
  echo "       Created: $SG_ID"
else
  echo "       Reusing: $SG_ID"
fi

aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$SSH_CIDR" --region "$AWS_REGION" 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true

# --- Launch instance ---
echo "[4/6] Launching EC2..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${VOLUME_GB},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "       InstanceId: $INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

# --- Elastic IP ---
echo "[5/6] Elastic IP..."
ALLOC_ID=$(aws ec2 allocate-address --domain vpc --region "$AWS_REGION" --query AllocationId --output text)
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$ALLOC_ID" --region "$AWS_REGION" >/dev/null
VALHALLA_IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOC_ID" --region "$AWS_REGION" --query 'Addresses[0].PublicIp' --output text)

# --- Save env file for later ---
STATE_FILE="${HOME}/valhalla-oregon-${INSTANCE_ID}.env"
cat > "$STATE_FILE" <<EOF
# Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
export AWS_REGION=$AWS_REGION
export INSTANCE_ID=$INSTANCE_ID
export ALLOC_ID=$ALLOC_ID
export VALHALLA_IP=$VALHALLA_IP
export VALHALLA_DOMAIN=$VALHALLA_DOMAIN
export KEY_NAME=$KEY_NAME
export SG_ID=$SG_ID
EOF

echo "[6/6] Done."
echo ""
echo "============================================"
echo "  Oregon Valhalla — infra ready"
echo "============================================"
echo "  Region:     $AWS_REGION (Oregon)"
echo "  Instance:   $INSTANCE_ID"
echo "  Public IP:  $VALHALLA_IP"
echo "  State file: $STATE_FILE"
echo ""
echo "  DNS (obrigatório antes do HTTPS):"
echo "    A record:  $VALHALLA_DOMAIN  ->  $VALHALLA_IP"
echo ""
echo "  SSH (from your Mac, not CloudShell):"
echo "    ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${VALHALLA_IP}"
echo ""
echo "  On the EC2, install Valhalla (1-3 hours first time):"
echo "    sudo apt-get update -y && sudo apt-get install -y git"
echo "    git clone <YOUR_REPO_URL> /tmp/trucker-easy"
echo "    sudo bash /tmp/trucker-easy/backend/valhalla-production/deploy.sh $VALHALLA_DOMAIN"
echo ""
echo "  Test:"
echo "    curl -s https://$VALHALLA_DOMAIN/status"
echo ""
echo "  App xcconfig:"
echo "    VALHALLA_SERVER_URL = https:||$VALHALLA_DOMAIN"
echo ""
echo "  Optional CloudFormation (HERE stub, not Valhalla engine):"
echo "    aws cloudformation deploy --stack-name trucker-routing-oregon \\"
echo "      --template-file truck-routing.yaml \\"
echo "      --parameter-overrides ValhallaPrimaryEndpoint=https://$VALHALLA_DOMAIN \\"
echo "      --capabilities CAPABILITY_NAMED_IAM --region $AWS_REGION"
echo "============================================"
