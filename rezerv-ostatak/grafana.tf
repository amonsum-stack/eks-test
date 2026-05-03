####################################################################
#
# Grafana — IRSA Setup
#
# Gives the Grafana pod read-only access to CloudWatch so it can
# query metrics and alarms without any static AWS credentials.
#
# What this creates:
#   1. IAM policy — CloudWatch read + EC2/RDS describe (for dimension lookups)
#   2. IRSA role  — trusted only by grafana ServiceAccount in monitoring ns
#   3. Kubernetes namespace manifest is in k8s/grafana/grafana.yaml
#
# After applying:
#   kubectl apply -f k8s/grafana/grafana.yaml
#   Then visit the Grafana ALB URL (kubectl get ingress -n monitoring)
#
####################################################################

####################################################################
# IAM Policy — CloudWatch read-only + dimension metadata
####################################################################

resource "aws_iam_policy" "grafana_cloudwatch" {
  name        = "eks-grafana-cloudwatch-policy"
  description = "Allow Grafana pod to read CloudWatch metrics and alarms"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchReadOnly"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Sid    = "LogsReadOnly"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        # Needed for CloudWatch dimension dropdowns in Grafana
        Sid    = "EC2TagsReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      },
      {
        # Needed for RDS dimension dropdowns in Grafana
        Sid    = "RDSReadOnly"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

####################################################################
# IRSA Role — trusted only by grafana SA in monitoring namespace
####################################################################

data "aws_iam_policy_document" "grafana_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks_oidc_provider.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:monitoring:grafana"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana_irsa" {
  name               = "eks-grafana-irsa"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume_role.json

  tags = {
    Name = "eks-grafana-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "grafana_irsa_policy" {
  policy_arn = aws_iam_policy.grafana_cloudwatch.arn
  role       = aws_iam_role.grafana_irsa.name
}

####################################################################
# Output — needed to patch grafana.yaml ServiceAccount annotation
####################################################################

output "grafana_irsa_role_arn" {
  description = "IAM role ARN to annotate the grafana ServiceAccount with"
  value       = aws_iam_role.grafana_irsa.arn
}
