#OIDC provider for IRSA (IAM Roles for Service Accounts)
# Used by ALB Controller, RDS, S3. Potentially used by EBS-CSI

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
