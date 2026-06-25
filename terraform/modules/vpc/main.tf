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

# --- Subnets publics (NAT, ALB, bastion k3s) - 2 AZ requis par l'ALB AWS ---
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index] # Variable corrigée au pluriel
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.name}-public-${count.index}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # Le tag indispensable pour l'ALB Public
  }
}

# --- Subnets privés compute (nœuds EKS, 2 AZ requis par EKS) ---
resource "aws_subnet" "private_compute" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_compute_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name                              = "${var.name}-private-compute-${count.index}"
    Tier                              = "private-compute"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# --- Subnets privés data (RDS, 2 AZ requis par subnet group) ---
resource "aws_subnet" "private_data" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name                              = "${var.name}-private-data-${count.index}"
    Tier                              = "private-data"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# --- NAT Gateway (Déployée dans le PREMIER subnet public) ---
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

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

# (L'association unique avec le count = 2 placé APRÈS la table de routage)
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Routing privé compute (sort via NAT, une seule table partagée par les 2 AZ) ---
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
  count          = 2
  subnet_id      = aws_subnet.private_compute[count.index].id
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