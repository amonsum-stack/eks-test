# Prometheus + Grafana Setup

Deploys the `kube-prometheus-stack` Helm chart into the `monitoring`
namespace. Includes Prometheus, Grafana, Alertmanager, Node Exporter,
and kube-state-metrics. The weather app exposes custom metrics scraped
by Prometheus and visualised in Grafana.

---

## Architecture

```
Nodes          → Node Exporter     → Prometheus → Grafana
Pods/K8s state → kube-state-metrics → Prometheus → Grafana
Weather App    → /metrics endpoint → Prometheus → Grafana
Alerts                             → Alertmanager → email/slack
```

CloudWatch agent continues running alongside — RDS metrics still
flow to CloudWatch since Prometheus cannot scrape RDS directly.

---

## Step 1 — Apply EBS CSI driver

```bash
terraform apply
```

Verify the addon is running:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

---

## Step 2 — Deploy Prometheus + Grafana

```bash
chmod +x eks/setup-prometheus.sh
./eks/setup-prometheus.sh
```

This script:
1. Verifies EBS CSI is running
2. Creates the `gp3` StorageClass and sets it as default
3. Installs `kube-prometheus-stack` via Helm
4. Prints the Grafana ALB URL

---

## Step 3 — Rebuild and push weather app image

The weather app now exposes `/metrics` — rebuild the image:

```bash
cd weather-app
docker build -t igior/weather-app:1.3 .
docker push igior/weather-app:1.3
```

Update `k8s/weather/weather.yaml` image tag to `1.3` and reapply:

```bash
kubectl apply -f k8s/weather/weather.yaml
```

---

## Step 4 — Apply the ServiceMonitor

```bash
kubectl apply -f k8s/weather/weather-servicemonitor.yaml
```

Verify Prometheus picked it up (allow 30-60 seconds):

```bash
kubectl port-forward -n monitoring \
  svc/kube-prometheus-stack-prometheus 9090:9090
```

Open http://localhost:9090 → Status → Targets → look for `weather/weather-app`

---

## Step 5 — Access Grafana

```bash
kubectl get ingress kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open `http://<ALB-URL>` — login with `admin / admin`, change password.

### Pre-built dashboards (included automatically)

| Dashboard | ID | What it shows |
|-----------|-----|---------------|
| Kubernetes / Compute Resources / Cluster | 17147 | CPU/memory across cluster |
| Kubernetes / Compute Resources / Namespace | 17375 | Per-namespace breakdown |
| Kubernetes / Nodes | 1860 | Node CPU, memory, disk, network |
| Node Exporter Full | 1860 | Detailed node metrics |
| Kubernetes / Pods | 17375 | Per-pod resource usage |

### Build a Belgrade Weather dashboard

1. **Dashboards → New → New Dashboard → Add visualization**
2. Select **Prometheus** datasource
3. Use these queries:

```promql
# Current temperature
belgrade_temperature_celsius

# HTTP request rate (requests/sec over 5 min)
rate(flask_http_request_total{job="weather-app"}[5m])

# 95th percentile latency
histogram_quantile(0.95,
  rate(flask_http_request_duration_seconds_bucket{job="weather-app"}[5m])
)

# Humidity
belgrade_humidity_percent

# Wind speed
belgrade_wind_speed_ms
```

---

## Port-forward access (no ALB needed)

```bash
# Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Grafana UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Alertmanager UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

---

## Upgrading

```bash
helm upgrade kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values eks/prometheus-values.yaml
```

---

## Cleanup

```bash
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring
# PVCs (EBS volumes) are not deleted automatically — clean up manually:
kubectl get pvc -n monitoring
aws ec2 describe-volumes --filters Name=tag:kubernetes.io/created-for/pvc/namespace,Values=monitoring
```
