#!/bin/bash
# create-db-secret.sh
#
# Run this after terraform apply to create the Kubernetes Secret
# containing the RDS credentials. Pulls values directly from
# AWS Secrets Manager so nothing sensitive touches your shell history.
#
# Creates the secret in two namespaces:
#   - demo    (existing apps, db-test-job etc.)
#   - weather (weather-fetcher and weather-aggregator CronJobs)
#
# Usage:
#   chmod +x create-db-secret.sh
#   ./create-db-secret.sh

set -euo pipefail

SECRET_ARN=$(terraform output -raw rds_secret_arn)
DB_ENDPOINT=$(terraform output -raw rds_endpoint)

echo "Fetching credentials from Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text)

DB_HOST=$(echo "$SECRET_JSON" | jq -r '.host')
DB_PORT=$(echo "$SECRET_JSON" | jq -r '.port')
DB_NAME=$(echo "$SECRET_JSON" | jq -r '.dbname')
DB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

echo "Creating secrets in namespaces: demo, weather..."

for NS in demo weather; do
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic postgres-credentials \
    --namespace="$NS" \
    --from-literal=host="$DB_HOST" \
    --from-literal=port="$DB_PORT" \
    --from-literal=dbname="$DB_NAME" \
    --from-literal=username="$DB_USER" \
    --from-literal=password="$DB_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "  Secret 'postgres-credentials' created in namespace '$NS'."
done

echo ""
echo "RDS endpoint: $DB_ENDPOINT"
