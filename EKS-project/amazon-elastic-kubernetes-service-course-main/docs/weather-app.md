# Belgrade Weather App

A lightweight Python/Flask app running on EKS that displays current
weather conditions for Belgrade, Serbia using the Open-Meteo API
(free, no API key required).

---

## Architecture

```
CronJob (every 10 min)
  └── weather-fetcher.py
        └── GET api.open-meteo.com
              └── writes JSON → ConfigMap: weather-data

Deployment (Flask + Gunicorn)
  └── app.py
        └── reads ConfigMap: weather-data
              └── renders index.html
                    └── Service → ALB Ingress → Browser
```

The Flask pod reads from the ConfigMap on every request. If the
ConfigMap doesn't exist yet (first deploy, before the CronJob runs),
it falls back to fetching directly from the API — so the first page
load always works.

---

## Step 1 — Build the Docker image

From the repo root:

```bash
cd weather-app
docker build -t weather-app:latest .
```

Test it locally before pushing:

```bash
docker run -p 8080:8080 weather-app:latest
# Open http://localhost:8080
# Note: the ConfigMap won't exist locally, it will fetch directly from Open-Meteo
```

---

## Step 2 — Push to a registry

### Option A — Docker Hub

```bash
docker tag weather-app:latest <your-dockerhub-username>/weather-app:latest
docker push <your-dockerhub-username>/weather-app:latest
```

### Option B — Amazon ECR

```bash
# Create the ECR repo (one time)
aws ecr create-repository --repository-name weather-app --region us-east-1

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Tag and push
docker tag weather-app:latest \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/weather-app:latest

docker push \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/weather-app:latest
```

For ECR, the nodes already have the `AmazonEC2ContainerRegistryReadOnly`
policy attached (from `nodes.tf`), so no extra credentials needed.

---

## Step 3 — Update the manifest

Edit `k8s/weather/weather.yaml` and replace both occurrences of
`<YOUR_IMAGE>` with your image path:

```yaml
# Docker Hub:
image: youruser/weather-app:latest

# ECR:
image: <account-id>.dkr.ecr.us-east-1.amazonaws.com/weather-app:latest
```

There are two places — the CronJob and the Deployment. Both use the
same image (the Dockerfile includes both `app.py` and `weather-fetcher.py`).

---

## Step 4 — Deploy

```bash
kubectl apply -f k8s/weather/weather.yaml
```

Watch the pod come up:

```bash
kubectl get pods -n weather -w
```

Trigger the fetcher manually (don't wait 10 minutes):

```bash
kubectl create job weather-fetch-now \
  --from=cronjob/weather-fetcher \
  -n weather
```

Check the fetcher logs:

```bash
kubectl logs -n weather -l app=weather-fetcher
```

Get the ALB URL:

```bash
kubectl get ingress weather-app -n weather \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open it in your browser — allow 60-90 seconds for the ALB to provision.

---

## Verify the ConfigMap

```bash
kubectl get configmap weather-data -n weather -o jsonpath='{.data.weather\.json}' | python3 -m json.tool
```

Should show the latest weather JSON with temperature, humidity, etc.

---

## Cleanup

```bash
kubectl delete namespace weather
```
