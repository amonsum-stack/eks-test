module "network" {
  source               = "./modules/network"
  vpc_cidr             = var.vpc_cidr
  vpc_name             = var.vpc_name
  cidr_subnet_public   = var.cidr_subnet_public
  us_availability_zone = var.us_availability_zone
}

module "additional_policies" {
  source                 = "./modules/policies"
  additional_policy_name = var.additional_policy_name
}

module "cluster_role" {
  source                 = "./modules/cluster_role"
  cluster_role_name      = var.cluster_role_name
  additional_policy_arns = [module.additional_policies.policy_arn]
}

module "eks" {
  source                      = "./modules/eks"
  cluster_name                = var.cluster_name
  cluster_role_arn            = module.cluster_role.cluster_role_arn
  vpc_id                      = module.network.vpc_id
  subnet_ids                  = module.network.public_subnet_id
  node_role_name              = var.node_role_name
  additional_policy_name      = var.additional_policy_name
  node_group_desired_capacity = var.node_group_desired_capacity
  node_group_max_size         = var.node_group_max_size
  node_group_min_size         = var.node_group_min_size
  ec2_instance_type           = var.ec2_instance_type
  node_ami_id                 = data.aws_ssm_parameter.node_ami.value

  depends_on = [module.cluster_role, module.additional_policies]
}

module "oidc" {
  source            = "./modules/oidc"
  oidc_issuer_url   = module.eks.oidc_issuer_url

  depends_on = [module.eks]
}

module "alb_controller" {
  source                  = "./modules/alb_controller"
  oidc_provider_arn       = module.oidc.oidc_provider_arn
  oidc_provider_url       = module.oidc.oidc_provider_url
  loadbalancer_policy_arn = module.additional_policies.policy_arn

  depends_on = [module.oidc]
}

module "sqs" {
  source            = "./modules/sqs"
  queue_name        = var.sqs_queue_name
  oidc_provider_arn = module.oidc.oidc_provider_arn
  oidc_provider_url = module.oidc.oidc_provider_url
  namespace         = var.sqs_namespace

  depends_on = [module.oidc]
}


data "aws_ssm_parameter" "node_ami" {
  name = "/aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

output "node_instance_role_arn" {
  value = module.eks.NodeInstanceRole
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "alb_controller_irsa_arn" {
  value = module.alb_controller.alb_controller_irsa_arn
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "sqs_producer_irsa_arn" {
  value = module.sqs.producer_irsa_arn
}

output "sqs_consumer_irsa_arn" {
  value = module.sqs.consumer_irsa_arn
}