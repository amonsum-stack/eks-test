# Container Insights — Setup Guide

Deploys the CloudWatch agent as a DaemonSet on every EKS node,
enabling pod, container, and node-level metrics in CloudWatch.

---

## What gets collected

| Level | Metrics |
|-------|---------|
| Cluster | Node count, total CPU/memory |
| Node | CPU, memory, disk, network per node |
| Pod | CPU and memory usage vs limits |
| Container | Per-container CPU and memory |

All metrics land in CloudWatch under the `ContainerInsights` namespace.

---

## Step 1 — Apply Terraform

```bash
terraform apply
```

This attaches `CloudWatchAgentServerPolicy` to the node instance role,
giving agent pods permission to push metrics to CloudWatch.

---

## Step 2 — Deploy the CloudWatch agent

```bash
chmod +x eks/setup-container-insights.sh
./eks/setup-container-insights.sh
```

This deploys 4 resources into the `amazon-cloudwatch` namespace:
- Namespace
- ConfigMap (what metrics to collect)
- ServiceAccount
- DaemonSet (one pod per node)

---

## Step 3 — Verify

```bash
# All 3 pods should be Running (one per node)
kubectl get pods -n amazon-cloudwatch

# Check agent logs for any errors
kubectl logs -n amazon-cloudwatch -l name=cloudwatch-agent --tail=20
```

---

## Step 4 — View metrics in CloudWatch

Open the Container Insights console:
https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#container-insights:infrastructure

You'll see a pre-built dashboard with:
- Cluster overview
- Per-node CPU and memory
- Per-pod resource usage
- Container-level drill-down

Metrics take 2-3 minutes to appear after the DaemonSet is running.

---

## Cleanup

```bash
kubectl delete namespace amazon-cloudwatch
terraform destroy
```
