output "registry_url" {
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
  description = "URL du registry ECR (sans le nom du repo) — ex: 172030247215.dkr.ecr.eu-west-1.amazonaws.com"
}

output "repository_urls" {
  value = {
    for k, v in aws_ecr_repository.this : k => v.repository_url
  }
  description = "Map service → URL complète du repo"
}