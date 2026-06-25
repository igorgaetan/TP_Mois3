output "vpc_id" {
  value = module.vpc.vpc_id
}


output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_compute_subnet_ids" {
  value = module.vpc.private_compute_subnet_ids
}

output "private_data_subnet_ids" {
  value = module.vpc.private_data_subnet_ids
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_secret_arn" {
  value = module.rds.secret_arn
}

output "k3s_public_ip" {
  value = module.ec2_k3s.public_ip
}

output "ecr_registry_url" {
  value = module.ecr.registry_url
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}