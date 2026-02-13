output "vpc_id" {
  value = aws_vcp.main.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.main.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.main.name
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "deployment_id" {
  value = random_id.deployment.hex
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.eks.name
}
