
module "network" {
  source               = "./modules/network"
  vpc_cidr             = var.vpc_cidr
  vpc_name             = var.vpc_name
  cidr_subnet_public   = var.cidr_subnet_public
  cidr_subnet_private  = var.cidr_subnet_private
  us_availability_zone = var.us_availability_zone
}

module "security_group" {
  source                         = "./modules/security_group"
  vpc_id                         = module.network.vpc_id
  ec2_security_group_name        = var.ec2_security_group_name
  ec2_security_group_description = var.ec2_security_group_description
}

module "ec2_instance" {
  source                   = "./modules/ec2_instance"
  count                    = 3
  public_subnet_id         = module.network.public_subnet_id[count.index % length(module.network.public_subnet_id)]  
  ec2_security_group_id    = module.security_group.ec2_security_group_id
  ami_id                   = data.aws_ssm_parameter.al2023_ami.value
  instance_type            = var.instance_type
  enable_public_ip_address = true
  key_name                 = aws_key_pair.ec2_kp.key_name
  iam_instance_profile     = aws_iam_instance_profile.instance_profile.name
  is_leader                = count.index == 0 
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
  source                          = "./modules/lb"
  vpc_id                          = module.network.vpc_id
  security_group_id               = [module.security_group.lb_security_group_id]
  lb_name                         = var.lb_name
  lb_type                         = var.lb_type
  public_subnet_id                = module.network.public_subnet_id
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

module "sns" {
    source = "./modules/sns"
    alert_email = var.alert_email
}

# Both the AMI and the key for EC2 is in the root main since all three instances need to get these files
# One AMI and one KEY pair is enough for all three instances, so we don't need to create them in the module
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

# Moved due to issues in lab 
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

resource "aws_iam_role_policy_attachment" "instance_role_secrets_manager" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = aws_iam_role.instance_role.name
} 

resource "aws_iam_role" "instance_role" {
  name               = "ec2_deploy_app_instance_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "ec2_deploy_app_instance_profile"
  role = aws_iam_role.instance_role.name
}




