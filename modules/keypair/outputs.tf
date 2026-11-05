output "bastion_key_name" {
  description = "Name of the bastion key pair"
  value       = aws_key_pair.bastion_keypair.key_name
}

output "runner_key_name" {
  description = "Name of the runner key pair"
  value       = aws_key_pair.runner_keypair.key_name
}

output "bastion_key_pair_id" {
  description = "ID of the bastion key pair"
  value       = aws_key_pair.bastion_keypair.id
}

output "runner_key_pair_id" {
  description = "ID of the runner key pair"
  value       = aws_key_pair.runner_keypair.id
}
