####################################################################
#
# EKS Pod Identity — Replaces IRSA for ALB Controller and Backup Job
#
# Pod Identity is simpler than IRSA:
#   - No OIDC provider needed
#   - No complex trust policy conditions
#   - No ServiceAccount annotations
#   - One aws_eks_pod_identity_association per SA instead
#
# To use this file:
#   1. Ensure pod-identity-addon.tf is applied first (installs the agent)
#   2. Remove or rename alb-controller.tf to alb-controller.tf.irsa
#      to avoid duplicate resource conflicts
#   3. Remove the IRSA role from s3-backup.tf (see comments below)
#
# The IAM policies (loadbalancer_policy, backup_s3_policy) are reused
# as-is — only the trust relationship and association change.
#
####################################################################

####################################################################
# ALB Controller IAM Role — Pod Identity trust policy
#
# Compare to IRSA trust policy which required:
#   - OIDC provider ARN as federated principal
#   - StringEquals conditions on :sub and :aud
#
# Pod Identity only needs:
#   - pods.eks.amazonaws.com as the service principal
#   - sts:AssumeRole + sts:TagSession actions
####################################################################

data "aws_iam_policy_document" "alb_controller_pod_identity_assume" {
  statement {
    effect  = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"  # Required for Pod Identity
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller_pod_identity" {
  name               = "eks-alb-controller-pod-identity"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_pod_identity_assume.json

  tags = {
    Name = "eks-alb-controller-pod-identity"
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller_pod_identity_policy" {
  policy_arn = aws_iam_policy.loadbalancer_policy.arn
  role       = aws_iam_role.alb_controller_pod_identity.name
}

# This is the key resource that replaces the SA annotation in IRSA.
# It tells EKS: "when a pod in kube-system uses the
# aws-load-balancer-controller ServiceAccount, give it this role"
resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = aws_eks_cluster.demo_eks.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller_pod_identity.arn

  tags = {
    Name = "alb-controller-pod-identity-association"
  }
}

####################################################################
# Backup Job IAM Role — Pod Identity trust policy
####################################################################

data "aws_iam_policy_document" "backup_pod_identity_assume" {
  statement {
    effect  = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup_pod_identity" {
  name               = "eks-backup-pod-identity"
  assume_role_policy = data.aws_iam_policy_document.backup_pod_identity_assume.json

  tags = {
    Name = "eks-backup-pod-identity"
  }
}

resource "aws_iam_role_policy_attachment" "backup_pod_identity_policy" {
  policy_arn = aws_iam_policy.backup_s3_policy.arn
  role       = aws_iam_role.backup_pod_identity.name
}

resource "aws_eks_pod_identity_association" "backup_job" {
  cluster_name    = aws_eks_cluster.demo_eks.name
  namespace       = "demo"
  service_account = "backup-job"
  role_arn        = aws_iam_role.backup_pod_identity.arn

  tags = {
    Name = "backup-job-pod-identity-association"
  }
}

####################################################################
# Outputs
####################################################################

output "alb_controller_pod_identity_role_arn" {
  description = "Pod Identity IAM role ARN for ALB controller"
  value       = aws_iam_role.alb_controller_pod_identity.arn
}

output "backup_pod_identity_role_arn" {
  description = "Pod Identity IAM role ARN for backup job"
  value       = aws_iam_role.backup_pod_identity.arn
}
