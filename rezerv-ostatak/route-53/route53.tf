####################################################################
# route53.tf
#
# Creates:
#   1. Public hosted zone for weather-app-test-belgrade.com
#   2. A record (alias) — weather.weather-app-test-belgrade.com → weather ALB
#
# Prerequisites:
#   - Domain registered in Route 53 console (one-time manual step)
#   - After terraform apply, copy the NS records output and set them
#     as the authoritative nameservers for the domain in:
#     Route 53 → Registered Domains → weather-app-test-belgrade.com → Name servers
#     (if they don't match already — they usually do when registered via Route 53)
#
# The ALB DNS name and zone ID are read from the weather ingress
# via a data source so this file has no hardcoded ALB values.
####################################################################

####################################################################
# Hosted Zone
####################################################################

resource "aws_route53_zone" "main" {
  name = "weather-app-test-belgrade.com"

  tags = {
    Name = "weather-app-test-belgrade-zone"
  }
}

####################################################################
# Data source — read the weather ALB details from the ingress
# The ALB is managed by the ALB controller so we look it up by tag.
####################################################################

data "aws_lb" "weather" {
  tags = {
    "ingress.k8s.aws/stack" = "weather/weather-app"
  }

  # Depends on the ingress existing — apply weather.yaml before terraform apply
  # or use depends_on if managing both in the same apply
}

####################################################################
# A record — weather subdomain → weather ALB (alias)
####################################################################

resource "aws_route53_record" "weather" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "weather.weather-app-test-belgrade.com"
  type    = "A"

  alias {
    name                   = data.aws_lb.weather.dns_name
    zone_id                = data.aws_lb.weather.zone_id
    evaluate_target_health = true
  }
}

####################################################################
# Outputs
####################################################################

output "route53_zone_id" {
  description = "Hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "NS records — set these in Route 53 Registered Domains if not already matching"
  value       = aws_route53_zone.main.name_servers
}

output "weather_url" {
  description = "Weather app URL after DNS propagates"
  value       = "https://weather.weather-app-test-belgrade.com"
}
