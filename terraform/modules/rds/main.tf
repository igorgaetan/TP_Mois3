# --- Mot de passe généré aléatoirement, jamais en dur ---
resource "random_password" "db" {
  length  = 24
  special = false
}

# --- Stocké dans Secrets Manager, jamais en clair dans le state lisible ---
resource "aws_secretsmanager_secret" "db" {
  name = "${var.name}-rds-credentials"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
  })
}

# --- Subnet group : où RDS a le droit de placer ses instances ---
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-rds-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = {
    Name = "${var.name}-rds-subnet-group"
  }
}

# --- Security group RDS : autorise uniquement les SG passés en paramètre ---
resource "aws_security_group" "rds" {
  name_prefix = "${var.name}-rds-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds-sg"
  }
}

resource "aws_security_group_rule" "rds_ingress" {
  for_each = { for idx, sg_id in var.allowed_security_group_ids : tostring(idx) => sg_id }

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = each.value
}

resource "aws_db_instance" "this" {
  identifier             = "${var.name}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az                = var.multi_az
  storage_encrypted       = true
  skip_final_snapshot     = true   # à passer à false en prod réelle
  backup_retention_period = 7
}