#!/bin/bash
# setup-grafana.sh
#
# Patches k8s/grafana/grafana.yaml with the IRSA role ARN from
# Terraform outputs, then applies all Grafana resources to the cluster.
#
# Run from the eks/ directory after terraform apply.
#
# Usage:
#   chmod +x setup-grafana.sh
#   ./setup-grafana.sh

set -euo pipefail

echo "Fetching Terraform outputs..."

GRAFANA_ROLE_ARN=$(terraform output -raw grafana_irsa_role_arn)

echo "  Grafana IRSA Role ARN: $GRAFANA_ROLE_ARN"

MANIFEST="../k8s/grafana/grafana.yaml"

echo "Patching manifest with role ARN..."
sed \
  -e "s|<grafana_irsa_role_arn>|${GRAFANA_ROLE_ARN}|g" \
  "$MANIFEST" | kubectl apply -f -

echo ""
echo "Waiting for Grafana pod to be ready..."
kubectl rollout status deployment/grafana -n monitoring --timeout=120s

echo ""
GRAFANA_URL=$(kubectl get ingress grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "<pending>")

echo "Done!"
echo ""
echo "Resources created in namespace: monitoring"
echo "  ServiceAccount:        grafana"
echo "  PersistentVolumeClaim: grafana-pvc (2Gi)"
echo "  Deployment:            grafana (grafana/grafana:10.4.2)"
echo "  Service:               grafana (ClusterIP)"
echo "  Ingress:               grafana (ALB)"
echo ""
if [ "$GRAFANA_URL" == "<pending>" ]; then
  echo "ALB is still provisioning. Check again in 60-90 seconds:"
  echo "  kubectl get ingress grafana -n monitoring"
else
  echo "Grafana URL: http://$GRAFANA_URL"
fi
echo ""
echo "Default credentials: admin / admin"
echo "You will be prompted to change the password on first login."
echo ""
echo "After logging in:"
echo "  1. Go to Dashboards → EKS → 'EKS Cluster Overview'"
echo "  2. Set the 'AutoScaling Group Name' variable to your ASG name:"
echo "     $(terraform output -raw NodeAutoScalingGroup 2>/dev/null || echo '<NodeAutoScalingGroup from terraform output>')"
echo "  3. The RDS instance ID is pre-set to 'eks-demo-postgres'"
