variable "lb_target_group_name" {
  description = "The name of the load balancer target group"
  type        = string
}

variable "lb_target_group_port" {
  description = "The port for the load balancer target group"
  type        = number
}

variable "lb_target_group_protocol" {
  description = "The protocol for the load balancer target group"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC"
  type        = string
}

variable "cidr_subnet_public" {
  description = "The CIDR blocks for the public subnets (LB + bastion)"
  type        = list(string)
}

variable "cidr_subnet_private" {
  description = "The CIDR blocks for the private subnets (EC2 app instances + RDS)"
  type        = list(string)
}

variable "us_availability_zone" {
  description = "The availability zones for the subnets"
  type        = list(string)
}

variable "ec2_security_group_name" {
  description = "The name of the EC2 security group"
  type        = string
}

variable "ec2_security_group_description" {
  description = "The description of the EC2 security group"
  type        = string
}

variable "instance_type" {
  description = "The instance type for the EC2 app instances"
  type        = string
}

variable "lb_name" {
  description = "The name of the load balancer"
  type        = string
}

variable "lb_type" {
  description = "The type of the load balancer"
  type        = string
}

variable "lb_listener_port" {
  description = "The port for the load balancer listener"
  type        = number
}

variable "lb_listener_protocol" {
  description = "The protocol for the load balancer listener"
  type        = string
}

variable "lb_listener_default_action_type" {
  description = "The default action type for the load balancer listener"
  type        = string
}

variable "db_name" {
  type        = string
  description = "Name of the initial Postgres database"
}

variable "db_username" {
  type        = string
  description = "Master username for RDS Postgres"
}

variable "db_engine" {
  type        = string
  description = "Database engine (e.g., postgres)"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class (e.g., db.t3.micro)"
}

variable "alert_email" {
  type        = string
  description = "Email address for RDS CloudWatch alerts"
}
