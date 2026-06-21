output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_id" {
  value = module.vpc.public_subnet_id
}

output "private_compute_subnet_id" {
  value = module.vpc.private_compute_subnet_id
}

output "private_data_subnet_ids" {
  value = module.vpc.private_data_subnet_ids
}