#!/usr/bin/env bash
# Terminate Oregon Valhalla EC2 + release Elastic IP (uses state file from bootstrap)
#
# Usage:
#   source ~/valhalla-oregon-i-xxxxxxxx.env
#   bash aws-oregon-teardown.sh

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-west-2}"

if [[ -z "${INSTANCE_ID:-}" ]]; then
  echo "ERROR: source the .env file from bootstrap first, or export INSTANCE_ID and ALLOC_ID"
  exit 1
fi

read -r -p "Terminate instance $INSTANCE_ID and release EIP? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || exit 0

if [[ -n "${ALLOC_ID:-}" ]]; then
  aws ec2 disassociate-address --association-id "$(aws ec2 describe-addresses --allocation-ids "$ALLOC_ID" --region "$AWS_REGION" --query 'Addresses[0].AssociationId' --output text)" --region "$AWS_REGION" 2>/dev/null || true
  aws ec2 release-address --allocation-id "$ALLOC_ID" --region "$AWS_REGION" || true
fi

aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
echo "Terminated $INSTANCE_ID"
