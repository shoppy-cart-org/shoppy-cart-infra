output "bastion_instance_id" {
  description = "ID of the bastion EC2 instance"
  value       = aws_instance.bastion_ec2.id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion"
  value       = aws_instance.bastion_ec2.public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the bastion"
  value       = aws_instance.bastion_ec2.private_ip
}