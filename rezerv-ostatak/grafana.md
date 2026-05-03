# Grafana — Setup Guide

Deploys Grafana inside the EKS cluster with the CloudWatch datasource
pre-configured via IRSA. No static AWS credentials anywhere.

---

## Architecture

```
Browser → ALB → Grafana Pod (monitoring ns)
                    │
                    └── IRSA role → CloudWatch API
                                      ├── AWS/EC2  (node metrics)
                                      ├── AWS/RDS  (postgres metrics)
                                      └── ContainerInsights (pod metrics)
```

Grafana uses the projected ServiceAccount token to assume the
`eks-grafana-irsa` IAM role, which has read-only CloudWatch access.
The ALB controller provisions the load balancer automatically from
the Ingress resource, same pattern as the demo app.

---

## Step 1 — Apply Terraform

```bash
terraform apply
```

Note the new output:

```
grafana_irsa_role_arn = "arn:aws:iam::<account-id>:role/eks-grafana-irsa"
```

---

## Step 2 — Deploy Grafana

```bash
chmod +x eks/setup-grafana.sh
./eks/setup-grafana.sh
```

This patches the manifest with the IRSA role ARN and applies all resources.

Verify the pod is running:

```bash
kubectl get pods -n monitoring
kubectl get ingress grafana -n monitoring
```

The ALB takes ~60–90 seconds to provision. The ingress ADDRESS column
will populate with a DNS name when it is ready.

---

## Step 3 — Log in

```bash
# Get the ALB URL
kubectl get ingress grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open `http://<ALB-URL>` in your browser.

Default credentials: **admin / admin**

You will be prompted to change the password on first login — do this.

---

## Step 4 — Open the pre-built dashboard

1. In the left sidebar go to **Dashboards → EKS → EKS Cluster Overview**
2. At the top of the dashboard, set the **AutoScaling Group Name** variable:

```bash
# Get your ASG name
terraform output NodeAutoScalingGroup
```

3. The **RDS Instance ID** is pre-set to `eks-demo-postgres` — no change needed.

The dashboard shows:
| Panel | Source | Metric |
|-------|--------|--------|
| Node CPU (max across ASG) | AWS/EC2 | CPUUtilization |
| Node Status Check Failed | AWS/EC2 | StatusCheckFailed |
| RDS CPU | AWS/RDS | CPUUtilization |
| RDS Free Storage | AWS/RDS | FreeStorageSpace |
| RDS Connections | AWS/RDS | DatabaseConnections |
| Pod CPU (cluster-wide) | ContainerInsights | pod_cpu_utilization |
| Pod Memory (cluster-wide) | ContainerInsights | pod_memory_utilization |

---

## Step 5 — Explore the CloudWatch datasource manually

To build your own panels:

1. Go to **Explore** (compass icon in sidebar)
2. Select **CloudWatch** as the datasource
3. Choose a namespace, metric, dimension, and statistic
4. Click **Run query**

Useful namespaces for this cluster:

| Namespace | What it covers |
|-----------|---------------|
| `AWS/EC2` | Node CPU, network, status checks |
| `AWS/RDS` | Postgres CPU, storage, connections |
| `ContainerInsights` | Per-pod and per-container CPU/memory |
| `AWS/ApplicationELB` | ALB request count, latency, 5xx errors |

---

## How IRSA works here

```
Grafana Pod
  └── Projected ServiceAccount token (signed by EKS OIDC issuer)
        └── sts:AssumeRoleWithWebIdentity
              └── IAM checks:
                    token issuer == registered OIDC provider?
                    sub == system:serviceaccount:monitoring:grafana?
                  └── Returns temporary credentials for eks-grafana-irsa
                        └── Grafana CloudWatch datasource uses these
                              to call cloudwatch:GetMetricData etc.
```

The credentials are automatically refreshed by the EKS token projector —
no expiry handling needed in Grafana config.

---

## Alerting (optional next step)

Grafana can also send its own alerts based on CloudWatch data:

1. Go to **Alerting → Contact points** → add an email or Slack webhook
2. Open a dashboard panel → **Edit** → **Alert** tab
3. Set a threshold and link to your contact point

This gives you Grafana-native alerts in addition to the CloudWatch
alarms already set up in `cloudwatch-alarms.tf`.

---

## Cleanup

```bash
kubectl delete namespace monitoring
terraform destroy   # removes the IRSA role and CloudWatch policy
```

Or to remove just Grafana without destroying the cluster:

```bash
kubectl delete namespace monitoring
# Then remove grafana.tf from your terraform config and run terraform apply
```
