####################################################################
#
# EKS Pod Identity Agent Addon
#
# This addon must be installed on the cluster before Pod Identity
# associations will work. It runs as a DaemonSet on every node
# and intercepts credential requests from pods, exchanging the
# pod's service account token for temporary AWS credentials.
#
# Without this addon, aws_eks_pod_identity_association resources
# will be created in Terraform but pods will not receive credentials.
#
# Note: Requires eks:CreateAddon permission. In some lab environments
# this may be blocked by SCPs. If so, install manually via the
# AWS Console: EKS → Clusters → demo-eks → Add-ons → Get more add-ons
# → search for "EKS Pod Identity Agent"
#
####################################################################

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.demo_eks.name
  addon_name    = "eks-pod-identity-agent"

  # Use the latest version — omitting this defaults to the latest
  # recommended version for your cluster's Kubernetes version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "eks-pod-identity-agent"
  }
}
