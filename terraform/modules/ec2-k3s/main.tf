# --- AMI Ubuntu 22.04 la plus récente ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name}-k3s-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "k3s" {
  name_prefix = "${var.name}-k3s-"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH depuis ton IP uniquement"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Trafic HTTP entrant (ingress nginx du k3s)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Trafic HTTPS entrant"
    from_port   = 443
    to_port     = 443
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
    Name = "${var.name}-k3s-sg"
  }
}

# --- Instance EC2 "vide" : Terraform ne fait QUE la provisionner.
#     L'installation de k3s sera faite par Ansible, pas ici. ---
resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.name}-k3s-host"
    Role = "k3s"          # Ansible utilisera ce tag pour l'inventaire dynamique
  }
}