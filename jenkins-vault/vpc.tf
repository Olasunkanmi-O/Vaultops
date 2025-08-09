#Creating the vpc
resource "aws_vpc" "jv-vpc" {
  cidr_block       = "12.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "jenkins-vault-vpc"
  }
}

# create public subnet 1
resource "aws_subnet" "pub_sub1" {
  vpc_id            = aws_vpc.jv-vpc.id
  cidr_block        = "12.0.1.0/24"
  availability_zone = var.az1

  tags = {
    Name = "jenkins-vault-pub_sub1"
  }
}

# create private subnet 1
resource "aws_subnet" "pri_sub1" {
  vpc_id            = aws_vpc.jv-vpc.id
  cidr_block        = "12.0.3.0/24"
  availability_zone = var.az1

  tags = {
    Name = "jenkins-vault-pri_sub1"
  }
}

# create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.jv-vpc.id

  tags = {
    Name = "jenkins-vault-igw"
  }
}

# create elastic ip for NAT gateway
resource "aws_eip" "eip" {
  domain = "vpc"

  tags = {
    Name = "jenkins-vault-eip"
  }
}

# create NAT gateway
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.pub_sub1.id

  tags = {
    Name = "jenkins-vault-ngw"
  }
  depends_on = [aws_eip.eip] # Ensuring the EIP is created first
}


# Create route table for public subnets
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.jv-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "jenkins-vault-pub_rt"
  }
}

# Create route table for private subnets
resource "aws_route_table" "pri_rt" {
  vpc_id = aws_vpc.jv-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw.id
  }
  tags = {
    Name = "jenkins-vault-pri_rt"
  }
}

# Creating route table association for public_subnet_1
resource "aws_route_table_association" "ass-public_subnet_1" {
  subnet_id      = aws_subnet.pub_sub1.id
  route_table_id = aws_route_table.pub_rt.id
}


# Creating route table association for private_subnet_1
resource "aws_route_table_association" "ass-private_subnet_1" {
  subnet_id      = aws_subnet.pri_sub1.id
  route_table_id = aws_route_table.pri_rt.id
}

