output "repository_names" {
  description = "Names of all ECR repositories."
  value       = { for name, repo in aws_ecr_repository.service : name => repo.name }
}

output "repository_urls" {
  description = "URLs of all ECR repositories."
  value       = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

output "repository_arns" {
  description = "ARNs of all ECR repositories."
  value       = { for name, repo in aws_ecr_repository.service : name => repo.arn }
}