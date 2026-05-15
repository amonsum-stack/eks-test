variable "instance_type" {}
variable "ami_id" {}
variable "subnet_id" {}
variable "ec2_security_group_id" {}
variable "key_name" {}
variable "iam_instance_profile" {}
variable "is_leader" {
  default = false
}

output "ec2_instance_id" {
  value = aws_instance.ec2_instance.id
}

# EC2 instance — placed in a private subnet, no public IP
# All inbound traffic via LB; SSH only via bastion
resource "aws_instance" "ec2_instance" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.ec2_security_group_id]
  associate_public_ip_address = false
  key_name                    = var.key_name
  iam_instance_profile        = var.iam_instance_profile

  user_data = var.is_leader ? templatefile("${path.module}/leader_user_data.sh", {}) : templatefile("${path.module}/worker_user_data.sh", {})

  tags = {
    Name = "EC2 Deploy App Instance"
    Role = var.is_leader ? "leader" : "worker"
  }
}
