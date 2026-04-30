#!/bin/bash
# setup-container-insights.sh
#
# Deploys the CloudWatch agent DaemonSet to the EKS cluster
# for Container Insights metrics collection.
#
# Must be run after:
#   1. terraform apply (attaches CloudWatchAgentServerPolicy to node role)
#   2. Nodes are in Ready state (kubectl get nodes)
#
# Usage:
#   chmod +x setup-container-insights.sh
#   ./setup-container-insights.sh

set -euo pipefail

CLUSTER_NAME=$(terraform output -raw NodeAutoScalingGroup | cut -d'-' -f1-2 2>/dev/null || echo "demo-eks")
CLUSTER_NAME="demo-eks"
REGION="us-east-1"

echo "Deploying Container Insights for cluster: ${CLUSTER_NAME} in ${REGION}"
echo ""

# Step 1 — Create the amazon-cloudwatch namespace
echo "Step 1: Creating amazon-cloudwatch namespace..."
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

# Step 2 — Create the CloudWatch agent ConfigMap
# This configures what metrics to collect and at what interval
echo "Step 2: Creating CloudWatch agent ConfigMap..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
data:
  cwagentconfig.json: |
    {
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "cluster_name": "${CLUSTER_NAME}",
            "metrics_collection_interval": 60
          }
        },
        "force_flush_interval": 5
      },
      "metrics": {
        "append_dimensions": {
          "AutoScalingGroupName": "\${aws:AutoScalingGroupName}",
          "InstanceId": "\${aws:InstanceId}",
          "InstanceType": "\${aws:InstanceType}",
          "NodeName": "\${ec2:tag:Name}"
        },
        "metrics_collected": {
          "cpu": {
            "measurement": [
              "cpu_usage_idle",
              "cpu_usage_iowait",
              "cpu_usage_user",
              "cpu_usage_system"
            ],
            "metrics_collection_interval": 60,
            "totalcpu": false
          },
          "disk": {
            "measurement": [
              "used_percent",
              "inodes_free"
            ],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "diskio": {
            "measurement": [
              "io_time",
              "write_bytes",
              "read_bytes",
              "writes",
              "reads"
            ],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "mem": {
            "measurement": [
              "mem_used_percent"
            ],
            "metrics_collection_interval": 60
          },
          "netstat": {
            "measurement": [
              "tcp_established",
              "tcp_time_wait"
            ],
            "metrics_collection_interval": 60
          },
          "swap": {
            "measurement": [
              "swap_used_percent"
            ],
            "metrics_collection_interval": 60
          }
        }
      }
    }
EOF

# Step 3 — Create the ServiceAccount for the CloudWatch agent
echo "Step 3: Creating CloudWatch agent ServiceAccount..."
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml

# Step 4 — Deploy the CloudWatch agent DaemonSet
echo "Step 4: Deploying CloudWatch agent DaemonSet..."
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml

# Step 5 — Wait for DaemonSet to be ready
echo ""
echo "Step 5: Waiting for CloudWatch agent pods to be ready..."
kubectl rollout status daemonset/cloudwatch-agent \
  -n amazon-cloudwatch \
  --timeout=120s

echo ""
echo "Container Insights deployed successfully!"
echo ""
echo "Verify pods are running:"
echo "  kubectl get pods -n amazon-cloudwatch"
echo ""
echo "Metrics will appear in CloudWatch under:"
echo "  Namespace: ContainerInsights"
echo "  Cluster:   ${CLUSTER_NAME}"
echo ""
echo "View the pre-built dashboard:"
echo "  https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#container-insights:infrastructure"
