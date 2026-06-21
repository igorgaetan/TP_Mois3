variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_public_key" {
  type        = string
  description = "Contenu de ta clé publique SSH (ex: cat ~/.ssh/id_ed25519.pub), pour qu'Ansible puisse s'y connecter"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "Ton IP publique en /32 (ex: 82.65.12.4/32), pour restreindre SSH"
}