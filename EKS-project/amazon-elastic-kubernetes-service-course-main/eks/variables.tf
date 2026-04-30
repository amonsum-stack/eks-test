####################################################################
#
# Variables used. All have defaults
#
####################################################################

# KK Playground. Cluster must be called 'demo-eks'
variable "cluster_name" {
  type        = string
  description = "Name of the cluster"
  default     = "demo-eks"
}

# KK Playground. Cluster role must be called 'eksClusterRole'
variable "cluster_role_name" {
  type        = string
  description = "Name of the cluster role"
  default     = "eksClusterRole"
}

# In KK playground and for some EKS labs, the role is not predefined.
# In some other EKS labs, the service role exists already.
# This variable is initialized as an environment variable source
# by check-environment.sh if it is required to be "true"
variable "use_predefined_role" {
  type        = bool
  description = "Whether to use predefined cluster service role, or create one."
  default     = false   #da se stavi na true i da se proba sa postojećom rolom, da se vidi da li će raditi
}

# KK Playground. Node role must be called 'eksWorkerNodeRole'
variable "node_role_name" {
  type        = string
  description = "Name of node role"
  default     = "eksWorkerNodeRole"
}

# KK Playground. Policy role must be called 'eksPolicy'
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
