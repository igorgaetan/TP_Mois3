module "vpc" {
  source = "../../modules/vpc"

  name = var.name
  azs  = var.azs
}