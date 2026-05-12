
module network {
  source = "./modules/network"
  vpc_cidr = var.vpc_cidr
  vpc_name = var.vpc_name
  cidr_subnet_public = var.cidr_subnet_public
  cidr_subnet_private = var.cidr_subnet_private
  us_availability_zone = var.us_availability_zone
}

module security_group {
  source = "./modules/security_group"
  vpc_id = module.network.vpc_id
  ec2_security_group_name = var.ec2_security_group_name
  ec2_security_group_description = var.ec2_security_group_description
}

module "ec2_instance" {
    source = "./modules/ec2_instance"
    count = 3
    public_subnet_id = module.network.public_subnet_id
    ec2_security_group_id = module.security_group.ec2_security_group_id
    ami_id = var.ami_id
    instance_type = var.instance_type
    key_name = var.key_name
    enable_public_ip_address = true
}

module "rds_instance" {
    source = "./modules/rds_instance"
    subnet_id = module.network.private_subnet_id
    security_group_id = module.security_group.rds_ingress_security_group_id
    db_instance_identifier = aws_db_instance.postgres.identifier
    db_name = var.db_name
    db_username = var.db_username
    db_password = random_password.db_password.result
    db_instance_class = var.db_instance_class
    db_engine = var.db_engine
}

module "lb" {
    source = "./modules/lb"
    vpc_id = module.network.vpc_id
    security_group_id = module.security_group.lb_security_group_id
    lb_name = var.lb_name
    lb_type = var.lb_type
    lb_listener_port = var.lb_listener_port
    lb_listener_protocol = var.lb_listener_protocol
    public_subnet_id = module.network.public_subnet_id
    lb_listener_default_action_type = var.lb_listener_default_action_type
}

module "lb_target_group" {
    source = "./modules/lb_target_group"
    vpc_id = module.network.vpc_id
    lb_target_group_name = var.lb_target_group_name
    lb_target_group_port = var.lb_target_group_port
    lb_target_group_protocol = var.lb_target_group_protocol
    ec2_instance_id = module.ec2_instance.ec2_instance_id
}

module "cloudwatch" {
    source = "./modules/cloudwatch"
    db_instance_identifier = aws_db_instance.postgres.identifier
}

module "sns" {
    source = "./modules/sns"
    alert_email = var.alert_email
}