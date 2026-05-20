#!/bin/bash
# Installs External Secrets Operator and syncs postgres credentials

set -euo pipefail

echo "======================================================"
echo " External Secrets Operator Setup"
echo "======================================================"

echo "Adding Helm repo..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

echo "Installing ESO..."
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --wait

echo "Verifying CRDs..."
kubectl get crds | grep external-secrets

echo "Creating namespaces..."
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace weather --dry-run=client -o yaml | kubectl apply -f -

echo "Applying SecretStore and ExternalSecret..."
kubectl apply -f external-secrets.yaml

echo "Waiting for secrets to sync..."
sleep 10

echo "Verifying..."
kubectl get secretstore -n weather
kubectl get secretstore -n demo
kubectl get externalsecret -n weather
kubectl get externalsecret -n demo
kubectl get secret postgres-credentials -n weather
kubectl get secret postgres-credentials -n demo

echo "======================================================"
echo " Done!"
echo "======================================================"