# Route 53 + ACM + HTTPS Setup

Adds a proper domain and HTTPS to the weather app:
`https://weather.weather-app-test-belgrade.com`

---

## Architecture

```
Browser
  └── https://weather.weather-app-test-belgrade.com
        └── Route 53 A record (alias)
              └── ALB (HTTPS:443 → HTTP:8080)
                    └── ACM certificate (*.weather-app-test-belgrade.com)
                          └── weather-app pods
```

HTTP on port 80 automatically redirects to HTTPS via the
`alb.ingress.kubernetes.io/ssl-redirect: '443'` annotation.

---

## Step 1 — Register the domain (manual, one-time)

1. Go to **AWS Console → Route 53 → Registered Domains**
2. Click **Register Domain**
3. Search for `weather-app-test-belgrade.com`
4. Add to cart, fill in contact details, complete purchase
5. Wait ~15 minutes for activation (you'll get an email)

Cost: ~$12/year for a `.com` domain.

> **Note:** When you register a domain through Route 53, it automatically
> creates a hosted zone and sets the nameservers correctly. Terraform will
> adopt this hosted zone or create a new one — see Step 3.

---

## Step 2 — Check if a hosted zone already exists

After registering, Route 53 may have auto-created a hosted zone.
Check before running terraform apply to avoid duplicates:

```bash
aws route53 list-hosted-zones --query \
  "HostedZones[?Name=='weather-app-test-belgrade.com.'].Id" \
  --output text
```

If a zone ID is returned, import it into Terraform state instead of creating a new one:

```bash
terraform import aws_route53_zone.main <ZONE_ID>
# Example: terraform import aws_route53_zone.main Z1234ABCDEF
```

If nothing is returned, Terraform will create it — no import needed.

---

## Step 3 — Terraform apply

```bash
terraform apply
```

This creates/adopts:
- Hosted zone for `weather-app-test-belgrade.com`
- Wildcard ACM certificate `*.weather-app-test-belgrade.com`
- DNS validation CNAME records (auto-validated, takes 2-5 min)
- A record alias: `weather.weather-app-test-belgrade.com` → weather ALB

Note the outputs:

```bash
terraform output acm_certificate_arn
terraform output weather_url
terraform output route53_name_servers
```

---

## Step 4 — Update the weather ingress

Patch the certificate ARN into the ingress:

```bash
CERT_ARN=$(terraform output -raw acm_certificate_arn)

kubectl annotate ingress weather-app -n weather \
  alb.ingress.kubernetes.io/certificate-arn="$CERT_ARN" \
  --overwrite
```

Or update `k8s/weather/weather.yaml` — replace `<ACM_CERTIFICATE_ARN>`
with the value from `terraform output acm_certificate_arn` and reapply:

```bash
kubectl apply -f k8s/weather/weather.yaml
```

The ALB will add an HTTPS listener within ~60 seconds.

---

## Step 5 — Verify

```bash
# Test HTTPS directly
curl -v https://weather.weather-app-test-belgrade.com

# Test HTTP redirect
curl -v http://weather.weather-app-test-belgrade.com
# Should return: 301 Moved Permanently → https://...
```

DNS propagation takes 1-5 minutes after terraform apply.

---

## Adding more subdomains later

To add `grafana.weather-app-test-belgrade.com` or any other subdomain:

1. The wildcard cert already covers it — no ACM changes needed
2. Add a new `aws_route53_record` block in `route53.tf`:

```hcl
resource "aws_route53_record" "grafana" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "grafana.weather-app-test-belgrade.com"
  type    = "A"

  alias {
    name                   = data.aws_lb.grafana.dns_name
    zone_id                = data.aws_lb.grafana.zone_id
    evaluate_target_health = true
  }
}
```

3. Add the certificate ARN and host rule to the Grafana ingress
4. `terraform apply`

---

## Cleanup

```bash
# Remove DNS records and cert (terraform destroy handles this)
terraform destroy -target=aws_route53_record.weather
terraform destroy -target=aws_acm_certificate_validation.main
terraform destroy -target=aws_acm_certificate.main
terraform destroy -target=aws_route53_zone.main

# Or full destroy
terraform destroy
```

> **Note:** Domains must be deleted manually in the Route 53 console —
> Terraform cannot delete registered domains.
