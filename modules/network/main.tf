variable "vpc_cidr" {}
variable "vpc_name" {}
variable "cidr_subnet_public" {
  type = list(string)
}
variable "cidr_subnet_private" {
  type = list(string)
}
variable "us_availability_zone" {}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public[*].id
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

# Public subnets 
resource "aws_subnet" "public" {
  count                   = length(var.cidr_subnet_public)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.cidr_subnet_public[count.index]
  availability_zone       = var.us_availability_zone[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-subnet-${count.index + 1}"
  }
}

# Private subnets 
resource "aws_subnet" "private" {
  count             = length(var.cidr_subnet_private)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.cidr_subnet_private[count.index]
  availability_zone = var.us_availability_zone[count.index]

  tags = {
    Name = "${var.vpc_name}-private-subnet-${count.index + 1}"
  }
}

# Internet Gateway — for public subnets only
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Public route table — routes internet traffic via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public" {
  count          = length(var.cidr_subnet_public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table — outbound route to NAT is added by the nat module
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

# Associate private subnets with the private route table
resource "aws_route_table_association" "private" {
  count          = length(var.cidr_subnet_private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
