output "runner_instance_id" {
  description = "ID of the runner EC2 instance"
  value       = aws_instance.runner_ec2.id
}

output "runner_private_ip" {
  description = "Private IP of the runner"
  value       = aws_instance.runner_ec2.private_ip
}

output "runner_ami_id" {
  description = "AMI ID used for the runner"
  value       = data.aws_ami.ubuntu.id
}