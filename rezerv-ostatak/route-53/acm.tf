####################################################################
# acm.tf
#
# Creates a wildcard ACM certificate for weather-app-test-belgrade.com
# and validates it automatically via DNS (Route 53).
#
# The wildcard *.weather-app-test-belgrade.com covers:
#   - weather.weather-app-test-belgrade.com
#   - any future subdomains (grafana, api, etc.)
#
# Validation takes 2-5 minutes after terraform apply.
# Terraform waits for validation before marking the resource complete.
####################################################################

resource "aws_acm_certificate" "main" {
  domain_name               = "weather-app-test-belgrade.com"
  subject_alternative_names = ["*.weather-app-test-belgrade.com"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "weather-app-test-belgrade-cert"
  }
}

####################################################################
# DNS validation records — written to Route 53 automatically
####################################################################

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  allow_overwrite = true
}

####################################################################
# Wait for certificate validation to complete before outputting ARN
####################################################################

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

####################################################################
# Output — used in ingress annotation and docs
####################################################################

output "acm_certificate_arn" {
  description = "ACM certificate ARN — paste into weather ingress annotation"
  value       = aws_acm_certificate_validation.main.certificate_arn
}
