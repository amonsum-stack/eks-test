#!/bin/bash
# setup-prometheus.sh
#
# Deploys kube-prometheus-stack via Helm into the monitoring namespace.
#
# Note: EBS CSI driver addon is blocked by lab SCP (iam:PassRole).
# Prometheus and Grafana run without persistence — data is lost on
# pod restart but fine for a lab environment.
#
# Prerequisites:
#   - kubectl configured for the cluster
#   - helm installed (helm version)
#
# Usage:
#   chmod +x setup-prometheus.sh
#   ./setup-prometheus.sh

set -euo pipefail

NAMESPACE="monitoring"
RELEASE="kube-prometheus-stack"
CHART_VERSION="58.4.0"

echo "======================================================"
echo " Prometheus + Grafana Setup"
echo "======================================================"
echo ""

####################################################################
# 1. Create monitoring namespace
####################################################################
echo "Creating monitoring namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

####################################################################
# 2. Add Helm repo
####################################################################
echo ""
echo "Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

####################################################################
# 3. Install / upgrade kube-prometheus-stack
####################################################################
echo ""
echo "Installing kube-prometheus-stack v${CHART_VERSION}..."
helm upgrade --install "$RELEASE" \
  prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --version "$CHART_VERSION" \
  --values prometheus-values.yaml \
  --timeout 10m \
  --wait

echo ""
echo "Waiting for Grafana pod to be ready..."
kubectl rollout status deployment \
  "${RELEASE}-grafana" \
  -n "$NAMESPACE" \
  --timeout=120s

####################################################################
# 4. Print summary
####################################################################
echo ""
echo "======================================================"
echo " Done!"
echo "======================================================"
echo ""
echo "Pods in monitoring namespace:"
kubectl get pods -n "$NAMESPACE"
echo ""

GRAFANA_URL=$(kubectl get ingress \
  "${RELEASE}-grafana" \
  -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "<pending>")

echo "Grafana URL:  http://${GRAFANA_URL}"
echo "Credentials: admin / admin  (change on first login)"
echo ""
echo "Prometheus port-forward:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
echo ""
echo "Next step: apply the weather app ServiceMonitor"
echo "  kubectl apply -f k8s/weather/weather-servicemonitor.yaml"
