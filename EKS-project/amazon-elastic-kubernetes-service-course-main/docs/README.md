# Belgrade Weather App — EKS Deployment Guide

A production-style EKS deployment running a Python/Flask weather application for Belgrade, Serbia. 

---

## Architecture Overview

```
Internet
   │
   ▼
AWS ALB (provisioned by ALB Controller)
   │
   ▼
EKS Worker Nodes (unmanaged, Auto Scaling Group)
   ├── weather-app        Flask deployment (3 replicas, HPA enabled)
   ├── weather-fetcher    CronJob — fetches Open-Meteo API every 10 min
   ├── weather-aggregator CronJob — aggregates hourly stats into RDS
   └── backup-job         CronJob — weekly pg_dump to S3
   │
   ├──► RDS Postgres 16 (private subnets, port 5432)
   ├──► S3 Backup Bucket (SSE, versioning, Glacier lifecycle)
   └──► AWS Secrets Manager (credentials via External Secrets Operator)

Observability:
   ├── Prometheus + Grafana (kube-prometheus-stack)
   └── CloudWatch Alarms → SNS → Email

Security:
   ├── Kyverno admission policies
   ├── Network policies (VPC CNI)
   └── IRSA (IAM Roles for Service Accounts)
```

---

## Prerequisites

- AWS CLI configured for `us-east-1`
- Terraform >= 1.0
- kubectl
- Helm v3
- jq

---

## Deployment Order

### 1. Provision the EKS Cluster

Initialize and apply Terraform:

```bash
terraform init
terraform plan
terraform apply
```

> **Takes 10–15 minutes.** Note all outputs when complete.

Set your alert email before applying (required by SNS/CloudWatch):

```bash
export TF_VAR_alert_email="you@example.com"
```

> **Note on lab environments:** The `modules/` directory handles cases where `eksClusterRole` may already exist from a previous lab. In a fresh AWS account you can replace the module references with a straightforward `aws_iam_role` resource — see the comments in `eks.tf` for details. Deploying this as it is, with modules wont change anything.

---

### 2. Configure kubectl and Join Nodes

Update your kubeconfig:

```bash
aws eks update-kubeconfig --region us-east-1 --name demo-eks
```

Edit `aws-auth-cm.yaml` and replace the placeholder with your `NodeInstanceRole` ARN from the Terraform output:

```yaml
- rolearn: arn:aws:iam::<account-id>:role/eksWorkerNodeRole
```

Apply it:

```bash
kubectl apply -f aws-auth-cm.yaml
```

Wait ~60 seconds then verify nodes are Ready:

```bash
kubectl get nodes -o wide
```

You should see 3 worker nodes in `Ready` state.

---

### 3. Install the AWS Load Balancer Controller

Add the Helm repo:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

Edit `alb-controller-values.yaml` and replace `<AlbControllerIrsaRoleArn>` with the value from Terraform output, then install:

```bash
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  -f alb-controller-values.yaml
```

Verify 2 replicas are running:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

> **Note:** If you previously applied `ingress-class-name.yaml` manually, delete it before running Helm — the chart creates the IngressClass itself:
> `kubectl delete ingressclass alb`

> After installing alb-controllers you can deploy `ingress-class-name.yaml`.

---

### 4. Install External Secrets Operator

ESO syncs credentials from AWS Secrets Manager into Kubernetes Secrets automatically.

> Create both namespaces kubectl createnamespace demo/weather

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --wait
```

Verify CRDs are installed:

```bash
kubectl get crds | grep external-secrets
```

Apply the SecretStore and ExternalSecret resources:

```bash
kubectl apply -f external-secrets.yaml
```

Verify the secret was synced:

```bash
kubectl get externalsecret postgres-credentials -n weather
kubectl get secret postgres-credentials -n weather
```

> **How credentials work:** ESO pods inherit the node instance role (`eksWorkerNodeRole`), which has `SecretsManagerReadWrite` attached. ESO uses these ambient credentials to pull `eks/postgres/credentials` from Secrets Manager and create the `postgres-credentials` Kubernetes Secret in each namespace.

---

### 5. Deploy the Weather Application

Apply the main manifest (namespace, service accounts, RBAC, CronJobs, Deployment, Service, Ingress):

```bash
kubectl apply -f weather.yaml
```

Initialise the RDS database schema (requires the `weather-fetcher` service account from the previous step):

```bash
kubectl apply -f init-db.yaml
kubectl logs -n weather -l job-name=weather-init-db
```

Trigger the weather fetcher immediately rather than waiting 10 minutes:

```bash
kubectl create job weather-fetch-now \
  --from=cronjob/weather-fetcher \
  -n weather
```

Get the ALB URL and test (allow 60–90 seconds for ALB provisioning):

```bash
kubectl get ingress weather-app -n weather
```

---

### 6. Enable Horizontal Pod Autoscaling

Check metrics-server is available:

```bash
kubectl top pods -n weather
```

If missing:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Apply the HPA:

```bash
kubectl apply -f weather-hpa.yaml
```

The HPA scales weather-app between 1–9 replicas based on CPU (>70%) and memory (>75%).

---

### 7. Enable Cluster Autoscaler

The Cluster Autoscaler scales nodes up when pods are Pending and scales down when nodes are underutilized.

```bash
kubectl apply -f cluster-autoscaler.yaml
```

Verify it discovered the ASG:

```bash
kubectl logs -n kube-system -l app=cluster-autoscaler | grep -i "found\|node group"
```

Test scale-up:

```bash
kubectl scale deployment weather-app -n weather --replicas=15
kubectl get nodes -w
```

Scale back down:

```bash
kubectl scale deployment weather-app -n weather --replicas=3
```

Nodes will be removed after ~10 minutes of low utilization.

---

### 8. Set Up S3 Backups

Weekly `pg_dump` streamed directly to S3, with Glacier archiving after 30 days.

```bash
chmod +x setup-backup.sh
./setup-backup.sh
```

Trigger a test backup immediately:

```bash
kubectl apply -f backup.yaml
kubectl logs -n weather job/backup-test -f
```

Verify in S3:

```bash
aws s3 ls s3://$(terraform output -raw backup_bucket_name)/backups/ --recursive
```

---

### 9. Deploy Prometheus and Grafana

```bash
chmod +x setup-prometheus.sh
./setup-prometheus.sh
```

Get the Grafana URL:

```bash
kubectl get ingress kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Login with `admin / admin`.

> **Note:** Persistence is disabled (`storageSpec: {}`, `persistence.enabled: false`) because the lab environment blocks the EBS CSI addon. In production, enable EBS CSI and set appropriate storage specs. Metrics re-populate quickly from live scraping after a pod restart.

---

### 10. Configure CloudWatch Alarms

Confirm your SNS subscription emails after `terraform apply` — AWS sends three confirmation emails (one per topic). Check your spam folder.

Verify alarms exist:

```bash
aws cloudwatch describe-alarms \
  --alarm-names \
    rds-cpu-high \
    rds-storage-low \
    rds-connections-high \
    rds-instance-down \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
```

---

### 11. Apply Network Policies

Enable the VPC CNI network policy enforcement first. Go to EKS → Clusters → demo-eks → Add-ons → vpc-cni → Edit configuration and set:

```json
{"enableNetworkPolicy": "true"}
```

Restart the daemonset to pick up the change:

```bash
kubectl rollout restart daemonset aws-node -n kube-system
```

Verify the `aws-eks-nodeagent` sidecar is running (shown as `2/2`):

```bash
kubectl get pods -n kube-system | grep aws-node
```

Apply the policies:

```bash
kubectl apply -f network-policies.yaml
```

> **Important:** Do not use Calico with this setup. The cluster uses the AWS VPC CNI which manages interfaces as `eni*`. Calico creates `cali*` interfaces and conflicts with the existing CNI, requiring node replacement to recover.

**Test enforcement:**

```bash
# Unmatched pod — should time out (default-deny-all blocks all egress)
kubectl run test-pod \
  --image=curlimages/curl \
  --namespace=weather \
  --labels="app=test-pod" \
  --rm -it --restart=Never \
  --command -- sh
# Inside: curl --max-time 5 https://google.com  →  should time out

# Weather-app — should succeed (egress 443 explicitly allowed)
kubectl exec -n weather \
  $(kubectl get pods -n weather -l app=weather-app -o jsonpath='{.items[0].metadata.name}') \
  -it -- python3 -c "
import urllib.request
r = urllib.request.urlopen('https://api.open-meteo.com/v1/forecast?latitude=44.8&longitude=20.4&current_weather=true', timeout=5)
print('SUCCESS:', r.status)
"
```

---

### 12. Apply Kyverno Policies

Install Kyverno:

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  -n kyverno \
  --create-namespace \
  --wait
```

Apply the policies:

```bash
kubectl apply -f kyverno-policies.yaml
```

Verify all policies are active:

```bash
kubectl get clusterpolicy
```

Check for violations against existing workloads:

```bash
kubectl get policyreport -A
```

**Policies applied:**

| Policy | Mode | What it enforces |
|--------|------|-----------------|
| require-resource-limits | enforce | All containers must have CPU and memory limits |
| require-app-label | enforce | All pods must have an `app` label |
| disallow-latest-tag | enforce | Images must use pinned version tags |
| disallow-privileged-containers | enforce | No privileged containers |
| disallow-root-user | audit | Containers should not run as root |
| require-readiness-probe | audit | Deployments should define readiness probes |

> **Testing tip:** If you need to run test pods in the `weather` namespace and Kyverno blocks them, temporarily patch policies to audit mode:
> ```bash
> kubectl patch clusterpolicy require-app-label \
>   -p '{"spec":{"validationFailureAction":"Audit"}}' --type merge
> kubectl patch clusterpolicy require-resource-limits \
>   -p '{"spec":{"validationFailureAction":"Audit"}}' --type merge
> kubectl patch clusterpolicy disallow-latest-tag \
>   -p '{"spec":{"validationFailureAction":"Audit"}}' --type merge
> ```
> Remember to switch back to `Enforce` when done.

---

## Security Summary

| Layer | Mechanism | What it protects |
|-------|-----------|-----------------|
| Network | VPC CNI network policies | Pod-to-pod and pod-to-internet traffic |
| Admission | Kyverno | Blocks non-compliant workloads at deploy time |
| AWS API | IRSA | Scopes AWS permissions per service account |
| Database | Private subnets + SG | RDS only reachable from node security group |
| Secrets | External Secrets Operator | No credentials stored in manifests or code |

---

## Cleanup

```bash
# Remove Kubernetes resources
kubectl delete namespace weather monitoring kyverno external-secrets

# Uninstall Helm releases
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall kyverno -n kyverno
helm uninstall external-secrets -n external-secrets

# Destroy infrastructure
terraform destroy
```

---

## Things to Add (Future Work)

- **CI/CD pipeline** — GitHub Actions to build and push the weather-app image on commit, trigger a rolling restart on the deployment
- **Route 53 + ACM** — custom domain with HTTPS. ALB terminates TLS, pods receive plain HTTP. Requires updating Ingress annotations for port 443 and HTTP→HTTPS redirect
- **EBS CSI addon** — enables persistent storage for Prometheus and Grafana so metrics survive pod restarts
- **Pod Identity** — simpler alternative to IRSA, no OIDC dependency, associations visible in EKS console
