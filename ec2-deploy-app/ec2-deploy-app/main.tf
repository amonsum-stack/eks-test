module "network" {
  source               = "./modules/network"
  vpc_cidr             = var.vpc_cidr
  vpc_name             = var.vpc_name
  cidr_subnet_public   = var.cidr_subnet_public
  cidr_subnet_private  = var.cidr_subnet_private
  us_availability_zone = var.us_availability_zone
}

module "bastion" {
  source           = "./modules/bastion"
  vpc_id           = module.network.vpc_id
  public_subnet_id = module.network.public_subnet_id[0]
  ami_id           = data.aws_ssm_parameter.al2023_ami.value
  key_name         = aws_key_pair.ec2_kp.key_name
}

# NAT Gateway in the first public subnet — single NAT to keep costs down
module "nat" {
  source                 = "./modules/nat"
  public_subnet_id       = module.network.public_subnet_id[0]
  private_route_table_id = module.network.private_route_table_id
}

module "security_group" {
  source                         = "./modules/security_group"
  vpc_id                         = module.network.vpc_id
  ec2_security_group_name        = var.ec2_security_group_name
  ec2_security_group_description = var.ec2_security_group_description
  bastion_sg_id                  = module.bastion.bastion_sg_id
}

module "ec2_instance" {
  source                = "./modules/ec2_instance"
  count                 = 3
  subnet_id             = module.network.private_subnet_id[count.index % length(module.network.private_subnet_id)]
  ec2_security_group_id = module.security_group.ec2_security_group_id
  ami_id                = data.aws_ssm_parameter.al2023_ami.value
  instance_type         = var.instance_type
  key_name              = aws_key_pair.ec2_kp.key_name
  iam_instance_profile  = aws_iam_instance_profile.instance_profile.name
  is_leader             = count.index == 0

  # EC2 instances must wait for the NAT Gateway to be ready before launching
  # so user_data scripts (Docker pull, Secrets Manager) can reach the internet
  depends_on = [module.nat]
}

module "rds" {
  source                = "./modules/rds"
  db_name               = var.db_name
  db_username           = var.db_username
  db_engine             = var.db_engine
  db_instance_class     = var.db_instance_class
  private_subnet_ids    = module.network.private_subnet_id
  rds_security_group_id = module.security_group.rds_security_group_id
}

module "lb" {
  source            = "./modules/lb"
  vpc_id            = module.network.vpc_id
  security_group_id = [module.security_group.lb_security_group_id]
  lb_name           = var.lb_name
  lb_type           = var.lb_type
  public_subnet_id  = module.network.public_subnet_id
}

module "lb_target_group" {
  source                          = "./modules/lb_target_group"
  vpc_id                          = module.network.vpc_id
  lb_arn                          = module.lb.lb_arn
  lb_target_group_name            = var.lb_target_group_name
  lb_target_group_port            = var.lb_target_group_port
  lb_target_group_protocol        = var.lb_target_group_protocol
  lb_listener_port                = var.lb_listener_port
  lb_listener_protocol            = var.lb_listener_protocol
  lb_listener_default_action_type = var.lb_listener_default_action_type
  ec2_instance_ids                = module.ec2_instance[*].ec2_instance_id
}

module "cloudwatch" {
  source                 = "./modules/cloudwatch"
  db_instance_identifier = module.rds.db_instance_identifier
  sns_topic_arn          = module.sns.sns_topic_arn
}

/*
module "cloudwatch_logs" {
  source        = "./modules/cloudwatch_logs"
  sns_topic_arn = module.sns.sns_topic_arn
}
*/

module "sns" {
  source      = "./modules/sns"
  alert_email = var.alert_email
}

# Shared resources — AMI and key pair used by both bastion and app instances
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "pem_file" {
  filename        = pathexpand("~/.ssh/ec2-aws.pem")
  file_permission = "600"
  content         = tls_private_key.key_pair.private_key_pem
}

resource "aws_key_pair" "ec2_kp" {
  key_name   = "ec2_deploy_app_key_pair"
  public_key = trimspace(tls_private_key.key_pair.public_key_openssh)
}

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "instance_role" {
  name               = "ec2_deploy_app_instance_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "ec2_deploy_app_instance_profile"
  role = aws_iam_role.instance_role.name
}

resource "aws_iam_role_policy_attachment" "instance_role_secrets_manager" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = aws_iam_role.instance_role.name
}

resource "aws_iam_role_policy_attachment" "instance_role_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.instance_role.name
}

output "bastion_public_ip" {
  description = "SSH entry point: ssh -i ~/.ssh/ec2-aws.pem ec2-user@<this-ip>"
  value       = module.bastion.bastion_public_ip
}

output "load_balancer_dns" {
  description = "Public URL for the weather app"
  value       = module.lb.lb_dns_name
}
