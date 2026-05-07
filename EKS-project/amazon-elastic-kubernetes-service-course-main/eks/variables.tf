####################################################################
#
# Variables used. All have defaults
#
####################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster"
  default     = "demo-eks"
}

variable "cluster_role_name" {
  type        = string
  description = "Name of the cluster role"
  default     = "eksClusterRole"
}

# In some other EKS labs, the service role exists already.
# This variable is initialized as an environment variable source
variable "use_predefined_role" {
  type        = bool
  description = "Whether to use predefined cluster service role, or create one."
  default     = false   
}

variable "node_role_name" {
  type        = string
  description = "Name of node role"
  default     = "eksWorkerNodeRole"
}

variable "additional_policy_name" {
    type = string
    description = "Name of IAM::Policy created for additional permissions"
    default = "eksPolicy"
}

variable "node_group_desired_capacity" {
  type        = number
  description = "Desired capacity of Node Group ASG."
  default     = 3
}
variable "node_group_max_size" {
  type        = number
  description = "Maximum size of Node Group ASG. Set to at least 1 greater than node_group_desired_capacity."
  default     = 4
}

variable "node_group_min_size" {
  type        = number
  description = "Minimum size of Node Group ASG."
  default     = 1
}

variable "ec2_instance_type" {
  type = string
  description = "ec2 instance type"
  default = "t3.medium"
}

# Name of the DB and username for the RDS Postgres instance. 
# These are used in the application and must match the values in the application configuration.

variable "db_name" {
  type        = string
  description = "Name of the initial Postgres database"
  default     = "appdb"
}

variable "db_username" {
  type        = string
  description = "Master username for RDS Postgres"
  default     = "appuser"
}

# Email address for all CloudWatch alarm and backup notifications.
variable "alert_email" {
  type        = string
  description = "Email address for all CloudWatch alarm and backup notifications"
  # Set via terraform.tfvars or environment variable:
  # Export TF_VAR_alert_email="you@example.com"
  # Do not set a default here — forces explicit acknowledgement
}
