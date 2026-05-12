variable "instance_type" {}
variable "ami_id" {}
variable "key_name" {}
variable "public_subnet_id" {}
variable "ec2_security_group_id" {}
variable "enable_public_ip_address" {}

output "ec2_instance_id" {
  value = aws_instance.ec2_instance.id
}

# Get the latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}


# Create an SSH key pair for logging into the EC2 instances
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key to local .ssh directory so it can be used by SSH clients
resource "local_sensitive_file" "pem_file" {
  filename        = pathexpand("~/.ssh/ec2-aws.pem")
  file_permission = "600"
  content         = tls_private_key.key_pair.private_key_pem
}

# Upload the public key of the key pair to AWS so it can be added to the instances
resource "aws_key_pair" "ec2_kp" {
  key_name   = "ec2_deploy_app_key_pair"
  public_key = trimspace(tls_private_key.key_pair.public_key_openssh)
}

# Create ec2 instance
resource "aws_instance" "ec2_instance" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.ec2_security_group_id]
  associate_public_ip_address = var.enable_public_ip_address

  # user_data =  da se instlaira docker i da se pokrene container sa aplikacijom

  tags = {
    Name = "EC2 Deploy App Instance"
  }
}

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "instance_role_secrets_manager" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = aws_iam_role.instance_role.name
} 

resource "aws_iam_role" "instance_role" {
  name               = "ec2_deploy_app_instance_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
}


