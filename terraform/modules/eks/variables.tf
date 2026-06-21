variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_compute_subnet_ids" {
  type        = list(string)
  description = "Subnets privés (2 AZ min) où vivront le control plane et les nœuds"
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}