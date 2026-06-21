variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "name" {
  type    = string
  default = "capstone-staging"
}

variable "azs" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b"]
}

variable "ssh_public_key" {
  type        = string
  description = "Ta clé SSH publique, pour Ansible"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "Ton IP publique en /32"
}