resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# --- Subnet public (NAT, ALB, bastion k3s) ---
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.azs[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public"
    Tier = "public"
  }
}

# --- Subnet privé compute (nœuds EKS / EC2 k3s) ---
resource "aws_subnet" "private_compute" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_compute_subnet_cidr
  availability_zone = var.azs[0]

  tags = {
    Name = "${var.name}-private-compute"
    Tier = "private-compute"
  }
}

# --- Subnets privés data (RDS, 2 AZ requis par subnet group) ---
resource "aws_subnet" "private_data" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-private-data-${count.index}"
    Tier = "private-data"
  }
}

# --- NAT Gateway (doit être dans le subnet PUBLIC) ---
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# --- Routing public ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Routing privé compute (sort via NAT) ---
resource "aws_route_table" "private_compute" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.name}-rt-private-compute"
  }
}

resource "aws_route_table_association" "private_compute" {
  subnet_id      = aws_subnet.private_compute.id
  route_table_id = aws_route_table.private_compute.id
}

# --- Routing privé data (PAS de sortie Internet, isolé) ---
resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-rt-private-data"
  }
}

resource "aws_route_table_association" "private_data" {
  count          = 2
  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data.id
}