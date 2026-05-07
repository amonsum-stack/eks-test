
#The use_eksClusterRole module is needed only if the lab already has the role defined.
# In other enviroments this module can be discarded.
module "use_eksClusterRole" {
  count  = var.use_predefined_role ? 1 : 0
  source = "./modules/use-service-role"

  cluster_role_name = var.cluster_role_name
}

module "create_eksClusterRole" {
  count  = var.use_predefined_role ? 0 : 1
  source = "./modules/create-service-role"

  cluster_role_name = var.cluster_role_name
  additional_policy_arns = [
    aws_iam_policy.loadbalancer_policy.arn
  ]
}

####################################################################
#                                                                  #
# Creates the EKS Cluster control plane                            #
#                                                                  #
####################################################################

resource "aws_eks_cluster" "demo_eks" {
  name     = var.cluster_name
  role_arn = var.use_predefined_role ? module.use_eksClusterRole[0].eksClusterRole_arn : module.create_eksClusterRole[0].eksClusterRole_arn

  vpc_config {
    subnet_ids = [
      data.aws_subnets.public.ids[0],
      data.aws_subnets.public.ids[1],
      data.aws_subnets.public.ids[2]
    ]
  }

  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
    
    # Lifecyle block to ignore changes to access_config, which is required to allow us to modify the aws-auth configmap 
    # after cluster creation without Terraform trying to reset it back to the default
    # This is required because the aws-auth configmap is what allows us to grant permissions to our worker nodes to join the cluster, 
    # and if Terraform tries to reset it back to the default then our worker nodes will not be able to join the cluster
    # This is a common issue when using Terraform to manage EKS clusters, and this is the recommended way to work around it
    # especially when doing things in predefined labs 
    lifecycle {
    ignore_changes = [access_config, vpc_config]
  }
}

