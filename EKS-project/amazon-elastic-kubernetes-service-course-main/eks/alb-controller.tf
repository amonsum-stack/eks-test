####################################################################
#
# AWS Load Balancer Controller - IRSA Setup
#
# This file sets up:
#   1. OIDC Identity Provider for the EKS cluster
#   2. IAM role for the ALB controller ServiceAccount (IRSA pattern)
#   3. Attaches the existing loadbalancer_policy to the IRSA role
#
# The existing loadbalancer_policy (eksPolicy) attached to the node
#
# After applying, install the controller with Helm
#
####################################################################

# Fetch the OIDC thumbprint for the cluster's issuer URL.
# Required to register the OIDC provider with IAM.
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.demo_eks.identity[0].oidc[0].issuer
}

# Register the cluster's OIDC endpoint as a trusted identity provider in IAM.
# This is what enables IRSA — pods can assume IAM roles via projected ServiceAccount tokens.
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.demo_eks.identity[0].oidc[0].issuer

  tags = {
    Name = "eks-oidc-provider"
  }
}

# Extract the OIDC provider hostname (without https://) for use in trust policy conditions.
locals {
  oidc_provider_url = replace(aws_iam_openid_connect_provider.eks_oidc_provider.url, "https://", "")
}

# Trust policy that allows ONLY the aws-load-balancer-controller ServiceAccount
# in the kube-system namespace to assume this role.
# This is the key security constraint of IRSA — scoped to one specific SA.
data "aws_iam_policy_document" "alb_controller_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# IAM role for the ALB Controller ServiceAccount.
# Trusted only by the specific ServiceAccount defined above.
resource "aws_iam_role" "alb_controller_irsa" {
  name               = "eks-alb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json

  tags = {
    Name = "eks-alb-controller-irsa"
  }
}

# Reuse the existing loadbalancer_policy (eksPolicy) — no new policy needed.
# This is the same policy already attached to the node role in nodes.tf.
resource "aws_iam_role_policy_attachment" "alb_controller_irsa_policy" {
  policy_arn = aws_iam_policy.loadbalancer_policy.arn
  role       = aws_iam_role.alb_controller_irsa.name
}

# Output the role ARN — needed for the Helm values file during controller install.
output "AlbControllerIrsaRoleArn" {
  description = "IAM role ARN to annotate the aws-load-balancer-controller ServiceAccount with"
  value       = aws_iam_role.alb_controller_irsa.arn
}
