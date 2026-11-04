output "runner_role_arn" {
  description = "ARN of the runner IAM role"
  value       = aws_iam_role.runner_role.arn
}

output "runner_instance_profile_name" {
  description = "Name of the runner instance profile"
  value       = aws_iam_instance_profile.runner_profile.name
}

output "terraform_role_arn" {
  description = "ARN of the Terraform IAM role"
  value       = aws_iam_role.terraform_role.arn
}