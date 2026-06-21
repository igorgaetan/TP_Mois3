variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_data_subnet_ids" {
  type        = list(string)
  description = "2 subnets privés isolés (2 AZ) pour le subnet group RDS"
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "SG autorisés à se connecter sur le port Postgres (ex: SG des nœuds EKS)"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = true
}