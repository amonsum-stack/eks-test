#!/bin/bash
# setup-prometheus.sh
#
# Deploys kube-prometheus-stack via Helm into the monitoring namespace.
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

echo "Creating monitoring namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

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
