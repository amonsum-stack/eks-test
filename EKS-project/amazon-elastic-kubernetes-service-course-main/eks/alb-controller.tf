####################################################################
#
# AWS Load Balancer Controller - IRSA Setup
#
# After applying, install the controller with Helm
#
####################################################################

# Trust policy that allows ONLY the aws-load-balancer-controller ServiceAccount
# in the kube-system namespace to assume this role.
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

# Reuse the existing loadbalancer_policy (eksPolicy).
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
