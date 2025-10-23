#!/usr/bin/env bash
set -euo pipefail

# Fill this OR let the next line auto-detect your account ID
ACCOUNT_ID="${ACCOUNT_ID:-}"
if [[ -z "$ACCOUNT_ID" ]]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
fi

REGION="${REGION:-us-east-1}"
BUCKET="bedrock-tfstate-${ACCOUNT_ID}-${REGION}"
TABLE="bedrock-tflock"

# Create S3 bucket (us-east-1 is special: no LocationConstraint allowed)
if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Bucket ${BUCKET} already exists (and you own it)."
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --create-bucket-configuration LocationConstraint="${REGION}" \
      --region "${REGION}"
  fi
fi

# Enable versioning (idempotent)
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

# Create DynamoDB lock table if needed
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "DynamoDB table ${TABLE} already exists."
else
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
fi

echo "BUCKET=${BUCKET}"
echo "TABLE=${TABLE}"