variable "vpc_id" {}
variable "ec2_security_group_name" {}
variable "ec2_security_group_description" {}
variable "bastion_sg_id" {}

output "ec2_security_group_id" {
  value = aws_security_group.ec2_sg.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "lb_security_group_id" {
  value = aws_security_group.lb.id
}

# EC2 security group
# - Port 8080: open to LB SG only (app traffic)
# - Port 22: open to bastion SG only (no direct public SSH)
resource "aws_security_group" "ec2_sg" {
  name        = var.ec2_security_group_name
  description = var.ec2_security_group_description
  vpc_id      = var.vpc_id

  ingress {
    description     = "App traffic from load balancer only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  ingress {
    description     = "SSH from bastion host only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.ec2_security_group_name
  }
}

# RDS security group — Postgres accessible from EC2 SG only
resource "aws_security_group" "rds" {
  name        = "${var.ec2_security_group_name}-rds"
  description = "Allow EC2 SG to access RDS Postgres"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from EC2 instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.ec2_security_group_name}-rds"
  }
}

# Load Balancer security group — HTTP open to internet, egress to EC2 on 8080
resource "aws_security_group" "lb" {
  name        = "${var.ec2_security_group_name}-lb"
  description = "Allow HTTP traffic to the load balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.ec2_security_group_name}-lb"
  }
}
