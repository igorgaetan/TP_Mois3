variable "name" {
  type = string
}

variable "services" {
  type        = list(string)
  description = "Liste des noms de services pour lesquels créer un repo ECR"
  default     = ["api-users", "api-orders", "api-products", "frontend"]
}