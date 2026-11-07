# Vpc 
resource "aws_vpc" "my_vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    { Name = var.vpc_name }
  )
}

# Public Subnet
resource "aws_subnet" "public_sub" {
  for_each                = var.public_sub_cidr
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name                     = each.key,
      "kubernetes.io/role/elb" = "1" # tag for load balancer discovery
    }
  )
}

# Private App Subnet
resource "aws_subnet" "private_app_sub" {
  for_each          = var.private_app_sub_cidr
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(
    var.tags,
    {
      Name                              = each.key,
      "kubernetes.io/role/internal-elb" = "1" # for internal 
    }
  )
}

# Private Data Subnet
resource "aws_subnet" "private_data_sub" {
  for_each          = var.private_data_sub_cidr
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(
    var.tags,
    { Name = each.key }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = merge(
    var.tags,
    { Name = var.igw_name }
  )
}

# Elastic IP
resource "aws_eip" "my_eip" {
  domain = "vpc"

  tags = merge(
    var.tags,
    { Name = "sc-eip" }
  )
}

# NAT Gateway
resource "aws_nat_gateway" "my_nat" {
  allocation_id = aws_eip.my_eip.id
  subnet_id     = aws_subnet.public_sub["public-sub-1"].id
  depends_on    = [aws_internet_gateway.my_igw]

  tags = merge(
    var.tags,
    { Name = "sc-nat-gw" }
  )
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = merge(
    var.tags,
    { Name = "sc-public-rt" }
  )
}

# Public Route
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_igw.id

}

# Public Route Table Association
resource "aws_route_table_association" "public_rt_associate" {
  for_each       = aws_subnet.public_sub
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

# Private App Route Table
resource "aws_route_table" "private_app_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = merge(
    var.tags,
    { Name = "sc-private-app-rt" }
  )
}

# Private App Route
resource "aws_route" "private_app_route" {
  route_table_id         = aws_route_table.private_app_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.my_nat.id

}

# Private App Route Table Association
resource "aws_route_table_association" "private_app_rt_associate" {
  for_each       = aws_subnet.private_app_sub
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app_rt.id
}

# Private Data Route Table
resource "aws_route_table" "private_data_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = merge(
    var.tags,
    { Name = "sc-private-data-rt" }
  )
}

# Private Data Route Table Association
resource "aws_route_table_association" "private_data_rt_associate" {
  for_each       = aws_subnet.private_data_sub
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_data_rt.id
}