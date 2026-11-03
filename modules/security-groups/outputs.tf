output "bastion_sg_id" {
  description = "Bastion SG ID"
  value = aws_security_group.bastion_sg.id
}

output "runner_sg_id" {
  description = "Runner SG ID"
  value = aws_security_group.runner_sg.id
}

output "lb_sg_id" {
  description = "LB SG ID"
  value = aws_security_group.lb_sg.id
}

output "workers_sg_id" {
  description = "Worker SG ID"
  value = aws_security_group.workers_sg.id
}