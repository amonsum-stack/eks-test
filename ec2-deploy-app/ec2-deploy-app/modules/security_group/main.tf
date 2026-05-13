variable "vpc_id" {}
variable "ec2_security_group_name" {}
variable "ec2_security_group_description" {}

output "ec2_security_group_id" {
  value = aws_security_group.ec2_sg.id
}

output "rds_security_group_id" {
    value = aws_security_group.rds.id
  
}

output "lb_security_group_id" {        
  value = aws_security_group.lb.id
}

# For SSH access to EC2, aws checks your ip
data "http" "cloudshell_ip" {
  url = "https://checkip.amazonaws.com/"
}

# Create a security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name        = var.ec2_security_group_name
  description = var.ec2_security_group_description
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${trimspace(data.http.cloudshell_ip.response_body)}/32"]  
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

# Create a security group for Load Balancer 
resource "aws_security_group" "lb" {
  name        = "${var.ec2_security_group_name}-lb"
  description = "Allow HTTP traffic to the load balancer"
  vpc_id      = var.vpc_id

  ingress {
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