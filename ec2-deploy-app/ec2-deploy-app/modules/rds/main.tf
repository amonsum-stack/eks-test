variable "db_username" {}
variable "db_name" {}
variable "db_engine" {}
variable "db_instance_class" {}
variable "private_subnet_ids" {}
variable "rds_security_group_id" {}


# DB Subnet Group 
resource "aws_db_subnet_group" "postgres" {
  name        = "postgres-subnet-group"
  description = "Private subnets for RDS Postgres"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "postgres-subnet-group"
  }
}


# Random password for the RDS master user
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"
}


# Store credentials in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "rds/postgres/credentials"
  description             = "RDS Postgres credentials"
  recovery_window_in_days = 0 # Delete instantly if you terraform destroy the secret, not for production 

  tags = {
    Name = "rds-postgres-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = var.db_name
  })
}

# RDS Postgres Instance


resource "aws_db_instance" "postgres" {
  identifier = "rds-${var.db_name}-postgres"

  engine         = var.db_engine
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100 
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [var.rds_security_group_id]

  # No public access — only reachable from within the VPC
  publicly_accessible = false

  # Backups — minimal for a lab
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Don't take a final snapshot when destroying (lab environment)
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "rds-${var.db_name}-postgres"
  }
}

output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgres.identifier
}