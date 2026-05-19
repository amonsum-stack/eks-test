variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC"
  type        = string
}

variable "cidr_subnet_public" {
  description = "The CIDR blocks for the public subnets"
  type        = list(string)
}

variable "us_availability_zone" {
  description = "The availability zones for the subnets"
  type        = list(string)
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "cluster_role_name" {
  type        = string
  description = "Name of the EKS cluster IAM role"
}

variable "node_role_name" {
  type        = string
  description = "Name of the worker node IAM role"
}

variable "additional_policy_name" {
  type        = string
  description = "Name of IAM::Policy created for additional permissions"
}

variable "node_group_desired_capacity" {
  type        = number
  description = "Desired capacity of Node Group ASG."
}

variable "node_group_max_size" {
  type        = number
  description = "Maximum size of Node Group ASG. Set to at least 1 greater than node_group_desired_capacity."
}

variable "node_group_min_size" {
  type        = number
  description = "Minimum size of Node Group ASG."
}

variable "ec2_instance_type" {
  type        = string
  description = "EC2 instance type for worker nodes"
}


variable "sqs_queue_name" {
  type        = string
  description = "Name of the SQS queue"
}

variable "sqs_namespace" {
  type        = string
  description = "Kubernetes namespace where producer and consumer run"
}

