####################################################################
# ebs-csi.tf
#
# Installs the AWS EBS CSI driver as an EKS managed addon.
# This enables PersistentVolumeClaims backed by EBS gp3 volumes.
#
# Used by:
#   - Prometheus (storage for metrics TSDB)
#   - Grafana (storage for dashboards and SQLite DB)
#   - Any future stateful workloads
#
# In the current lab EBS CSI is disabled by SCP. This is kept as a reference point on what 
# can be done in the future. Since EBS-CSI addon can support PV and PVC provisioning,
# which is needed for stateful workloads. 
# When applied successfully, this file will create:
#   - An IAM role with the AmazonEBSCSIDriverPolicy managed policy attached
#   - An EKS addon for the aws-ebs-csi-driver, using that role
# Kubernetes deployments can use the EBS CSI driver to provision EBS volumes for PersistentVolumeClaims.
####################################################################

####################################################################
# IRSA Role — trusted by ebs-csi-controller-sa in kube-system
####################################################################

/* < remove this to enable EBS CSI >

data "aws_iam_policy_document" "ebs_csi_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_irsa" {
  name               = "eks-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Name = "eks-ebs-csi-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_irsa.name
}

####################################################################
# EKS Addon — aws-ebs-csi-driver
####################################################################


resource "aws_eks_addon" "ebs_csi" {
   cluster_name             = aws_eks_cluster.demo_eks.name
   addon_name               = "aws-ebs-csi-driver"
   service_account_role_arn = aws_iam_role.ebs_csi_irsa.arn
   resolve_conflicts_on_update = "PRESERVE"
   tags = { Name = "eks-ebs-csi-driver" }
   depends_on = [aws_iam_role_policy_attachment.ebs_csi_policy]
 }

####################################################################
# EBS-CSI Output
####################################################################

output "ebs_csi_role_arn" {
  description = "EBS CSI driver IRSA role ARN"
  value       = aws_iam_role.ebs_csi_irsa.arn
}

< remove this to enable EBS CSI > */