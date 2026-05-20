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
> Remember to import your email address for sns notifications
```bash
export TF_VAR_alert_email="you@example.com"
```

## Deployment Order

### 1. Provision the EKS Cluster

Initialize and apply Terraform:

```bash
terraform init
terraform plan
terraform apply
```

> **Takes around 20 minutes.** This is due to EBS addon not being able to register to EKS cluter nodes. After terraform timesout, you can go with 
```bash
aws eks update-kubeconfig --region us-east-1 --name eks-demo-cluster
```
and then apply aws-auth-cm.yaml with approriate `NodeInstanceRole` this will register the nodes to the cluster and EBS addon pods will start working normally. 

You can check with 
```bash
kubectl get nodes -o wide
```
```bash
kubectl get pods -n kube-system | grep ebs
```
> This should display csi-controller and nodes running.

### 3. Install the AWS Load Balancer Controller with alb-setup.sh

```bash
chmod +x alb-setup.sh
./alb-setup.sh
```

### 4. Install External Secrets Operator with script

ESO syncs credentials from AWS Secrets Manager into Kubernetes Secrets automatically.

```bash
chmod +x create-secrets.sh
./create-secrets.sh
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
You can also do this from the Web-UI. Go to ec2 > loadbalancers in the main page you will see ALB URL copy that in the browser.
Dont forget to add http://ALB-URL


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

The HPA scales weather-app between 1–9 replicas based on CPU (>70%) and memory (>75%). If you want to test the cluster autoscaler you need to change the max pods. 
```bash
kubectl patch hpa weather-app-hpa -n weather -p '{"spec":{"maxReplicas":20}}'
```

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
check if its running 
```bash
kubectl get pods -n kube-system | grep cluster-autoscaler
```
check the logs

```bash
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50
```

Test scale-up:

```bash
kubectl scale deployment weather-app -n weather --replicas=20
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
You can verify this on the Web-UI. Go for S3 and you should see a backup bucket created with other contents signifiying date

---

### 9. Deploy Prometheus and Grafana

> Before deploying we can add taints/tolerations for monitoring. After the nodes have been registered pick a node that you want to taint for monitoring

```bash
kubectl label node <node-name> NodeType=monitoring
kubectl taint node <node-name> dedicated=monitoring:NoSchedule
```
> Verify

```bash
kubectl describe node <node-name> | grep -A2 "Taints\|Labels"
```
> Inititate the script (tolerations are present in the values)

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
# Inside pod use: curl --max-time 5 https://google.com  ->  should time out

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
### 13. CI/CD Pipeline

A CI/CD pipeline has been added in the `.github/workflows/deploy.yml` which triggers any time a change is pushed to the `weather-app` directory on `main`. GitHub Actions will lint and test the code, build and push the image to Docker Hub, then roll it out to the EKS cluster. Note that the cluster needs to be up and running for the deploy step to succeed.

**Image tagging:** The pipeline tags each image twice — once with the Git SHA (used for deployment) and once as `:latest` (for Docker Hub convenience). Kyverno's `disallow-latest-tag` policy blocks `:latest` from being admitted to the cluster, so only the pinned SHA tag ever reaches EKS. This is intentional. The pipeline works, but if someone would get the image separetly and try to run it, policies would block it.

Keep in mind that credentials in GitHub Actions need to be set according to your deployment. This includes AWS and Docker credentials (set in repo Settings -> Secrets).

Credentials can also be sorted by creating a dedicated IAM user, however i wasn't been able to test this since SCP in the lab doesn't allow this.

**Option A — Create a dedicated IAM user for GitHub Actions:**

```bash
aws iam create-user --user-name github-actions-deploy
aws iam create-access-key --user-name github-actions-deploy

aws iam attach-user-policy \
  --user-name github-actions-deploy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

Then add the user to `aws-auth-cm.yaml` below the instance role entry:

```yaml
mapUsers: |
  - userarn: arn:aws:iam::<account-id>:user/github-actions-deploy
    username: github-actions-deploy
    groups:
      - system:masters
```

**Option B — Reuse your existing AWS access key.** Place your current `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` directly in GitHub Secrets. In this case no `aws-auth` changes are needed since your user is already trusted.

> The lab environment had restrictions on creating new IAM users, so Option B was used here.

**Kyverno Policies applied:**

| Policy | Mode | What it enforces |
|--------|------|-----------------|
| require-resource-limits | enforce | All containers must have CPU and memory limits |
| require-app-label | enforce | All pods must have an `app` label |
| disallow-latest-tag | enforce | Images must use pinned version tags |
| disallow-privileged-containers | enforce | No privileged containers |
| disallow-root-user | audit | Containers should not run as root |
| require-readiness-probe | audit | Deployments should define readiness probes |

> **Testing tip:** If you need to run test pods in the `weather` namespace and Kyverno blocks them, temporarily patch policies to audit mode:
 ```bash
 kubectl patch clusterpolicy require-app-label \
   -p '{"spec":{"validationFailureAction":"Audit"}}' --type merge
 kubectl patch clusterpolicy require-resource-limits \
   -p '{"spec":{"validationFailureAction":"Audit"}}' --type merge
 kubectl patch clusterpolicy disallow-latest-tag \
   -p '{"spec":{"validationFailureAction":"Audit"}}' --type merge
```
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

- **Route 53 + ACM** — custom domain with HTTPS. ALB terminates TLS, pods receive plain HTTP. Requires updating Ingress annotations for port 443 and HTTP→HTTPS redirect
- **Pod Identity** — simpler alternative to IRSA, no OIDC dependency, associations visible in EKS console. Unable due to lab limitations
- **Grafana-setup** - In the production setting grafana should go over vpn and internal Load balancer that is reachable within VPC. Or maybe with a office vpn and public load balancer that is locked to specific ip range, along with SSO that is present on Grafana. Route 53 and acm should be enabled i think.