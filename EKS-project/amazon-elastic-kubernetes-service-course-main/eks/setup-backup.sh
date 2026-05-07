#!/bin/bash
# setup-backup.sh
#
# Patches backup.yaml with real values from Terraform outputs,
# then applies the ServiceAccount and CronJob to the cluster.
#
# Usage:
#   chmod +x setup-backup.sh
#   ./setup-backup.sh

set -euo pipefail

echo "Fetching Terraform outputs..."

BACKUP_ROLE_ARN=$(terraform output -raw backup_irsa_role_arn)
BUCKET_NAME=$(terraform output -raw backup_bucket_name)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "  Role ARN:    $BACKUP_ROLE_ARN"
echo "  Bucket:      $BUCKET_NAME"
echo "  Account ID:  $AWS_ACCOUNT_ID"

MANIFEST="backup.yaml"

echo "Patching manifest..."
sed \
  -e "s|<backup_irsa_role_arn>|${BACKUP_ROLE_ARN}|g" \
  -e "s|<backup_bucket_name>|${BUCKET_NAME}|g" \
  -e "s|<aws_account_id>|${AWS_ACCOUNT_ID}|g" \
  "$MANIFEST" | kubectl apply -f -

echo ""
echo "Done. Resources created:"
echo "  ServiceAccount: backup-job (namespace: weather)"
echo "  CronJob:        postgres-backup (schedule: Sundays 02:00 UTC)"
echo ""
echo "To test immediately:"
echo "  kubectl apply -f backup.yaml  # then trigger the test Job"
echo "  kubectl logs -n weather job/backup-test"
