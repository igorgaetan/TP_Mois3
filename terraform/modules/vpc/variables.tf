variable "name" {
  type        = string
  description = "Préfixe pour nommer les ressources (ex: capstone-staging)"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "2 AZ à utiliser, ex: [\"eu-west-1a\", \"eu-west-1b\"]"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "private_compute_subnet_cidrs" {
  type        = list(string)
  description = "2 CIDR pour les subnets EKS (1 par AZ, exigé par AWS pour le control plane)"
  default     = ["10.0.1.0/24", "10.0.4.0/24"]
}

variable "private_data_subnet_cidrs" {
  type        = list(string)
  description = "2 CIDR pour les subnets RDS (2 AZ différentes obligatoire)"
  default     = ["10.0.2.0/24", "10.0.3.0/24"]
}