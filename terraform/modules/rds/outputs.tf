output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "secret_arn" {
  value       = aws_secretsmanager_secret.db.arn
  description = "ARN du secret à lire depuis Ansible (jamais le mot de passe en clair ici)"
}

output "security_group_id" {
  value = aws_security_group.rds.id
}