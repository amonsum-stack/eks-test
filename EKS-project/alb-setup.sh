#!/bin/bash

# setup script for ALB controller

set -euo pipefail

echo "======================================================"
echo " ALB Ingress Controller Setup"
echo "======================================================"

echo "Fetching Terraform outputs..."
ALB_IRSA=$(terraform output -raw alb_controller_irsa_arn)
VPC_ID=$(terraform output -raw vpc_id)

echo "  ALB IRSA Role ARN: $ALB_IRSA"
echo "  VPC ID:            $VPC_ID"

echo "Patching values file..."
sed \
  -e "s|<AlbControllerIrsaRoleArn>|${ALB_IRSA}|g" \
  -e "s|<output from the VPC-ID terraform output>|${VPC_ID}|g" \
  alb-controller-values.yaml.template > alb-controller-values.yaml

echo "Adding Helm repo..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "Installing ALB Ingress Controller..."
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  -f alb-controller-values.yaml

echo "Waiting for rollout..."
kubectl rollout status deployment aws-load-balancer-controller \
  -n kube-system \
  --timeout=120s

echo ""
echo "======================================================"
echo " Done!"
echo "======================================================"
kubectl get deployment -n kube-system aws-load-balancer-controller

echo "Applying ingress-class-name.yaml"
kubectl apply -f ingress-class-name.yaml

echo "Verify ingress-class"
kubectl get ingressclass alb