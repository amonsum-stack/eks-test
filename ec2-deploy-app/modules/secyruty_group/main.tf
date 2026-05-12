variable "vpc_id" {}
variable "ec2_security_group_name" {}
variable "ec2_security_group_description" {}

output "ec2_security_group_id" {
  value = aws_security_group.ec2_sg.id
}

output "rds_security_group_id" {
    value = aws_security_group.rds.id
  
}

data "http" "cloudshell_ip" {
  url = "https://checkip.amazonaws.com/"
}

# Create a security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name        = var.ec2_security_group_name
  description = var.ec2_security_group_description
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.http.cloudshell_ip.body]
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

# Create a security group for RDS that allows access from EC2 SG
resource "aws_security_group" "rds" {
  name        = "${var.ec2_security_group_name}-rds"
  description = "Allow EC2 SG to access RDS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
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