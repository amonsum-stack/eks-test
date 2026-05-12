variable "vpc_cidr" {}
variable "vpc_name" {}
variable "cidr_subnet_public" {}
variable "cidr_subnet_private" {}
variable "us_availability_zone" {}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private[*].id
}


# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = var.vpc_name
  }
}

# Create a public subnet for app
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.cidr_subnet_public
  availability_zone = var.us_availability_zone[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-subnet"
  }
}

# Create a private subnet for RDS
resource "aws_subnet" "private" {
  count = 3
  vpc_id = aws_vpc.main.id
  cidr_block = var.cidr_subnet_private[count.index]
  availability_zone = var.us_availability_zone[count.index]

  tags = {
    Name = "${var.vpc_name}-private-subnet"
  }
}


# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Route Table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# Associate public subnet with route table
resource "aws_route_table_association" "public" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table (no internet access)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

# Associate private subnet with route table
resource "aws_route_table_association" "private" {
  count = 3
  subnet_id =  aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
} # proveri kako resursi iz public mogu da komuniciraju sa bazom u private subnetu, da li treba da se doda neka ruta



