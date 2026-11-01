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