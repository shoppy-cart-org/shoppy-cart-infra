output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private App Subnet IDs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private Data Subnet IDs"
  value       = module.vpc.private_data_subnet_ids
}

output "nat_id" {
  description = "NAT Gateway ID"
  value       = module.vpc.nat_id
}

output "bastion_sg_id" {
  description = "Bastion SG ID"
  value       = module.security-groups.bastion_sg_id
}

output "runner_sg_id" {
  description = "Runner SG ID"
  value       = module.security-groups.runner_sg_id
}

output "lb_sg_id" {
  description = "LoadBalancer SG ID"
  value       = module.security-groups.lb_sg_id
}

output "workers_sg_id" {
  description = "Workers SG ID"
  value       = module.security-groups.workers_sg_id
}

output "runner_role_arn" {
  description = "ARN of the runner IAM role"
  value       = module.iam.runner_role_arn
}

output "runner_instance_profile_name" {
  description = "Name of the runner instance profile (used in Phase 6)"
  value       = module.iam.runner_instance_profile_name
}

output "terraform_role_arn" {
  description = "ARN of the Terraform IAM role (used in Phase 8)"
  value       = module.iam.terraform_role_arn
}