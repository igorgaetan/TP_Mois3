module "vpc" {
  source = "../../modules/vpc"

  name = var.name
  azs  = var.azs
}

module "eks" {
  source = "../../modules/eks"

  name                        = var.name
  vpc_id                      = module.vpc.vpc_id
  private_compute_subnet_ids = module.vpc.private_compute_subnet_ids
}

module "rds" {
  source = "../../modules/rds"

  name                        = var.name
  vpc_id                      = module.vpc.vpc_id
  private_data_subnet_ids    = module.vpc.private_data_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
}

module "ec2_k3s" {
  source = "../../modules/ec2-k3s"

  name              = var.name
  vpc_id             = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_id
  ssh_public_key    = var.ssh_public_key
  allowed_ssh_cidr  = var.allowed_ssh_cidr
}