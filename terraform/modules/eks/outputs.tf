output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "node_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "aws_lb_controller_role_arn" {
  description = "ARN du rôle IAM pour le AWS Load Balancer Controller"
  value       = aws_iam_role.aws_lb_controller.arn
}