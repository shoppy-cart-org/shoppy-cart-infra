variable "vpc_id" {
  description = "VPC ID"
}

variable "bastion_sg" {
  description = "Bastion Security Group"
  type = string
  default = "bastion-sg"
}

variable "my_ip" {
  description = "My IP Address"
  type = string

  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && endswith(var.my_ip, "/32")
    error_message = "my_ip must be a valid /32 CIDR (e.g., 1.2.3.4/32)."
}
}

variable "runner_sg" {
  description = "Runner Security Group"
  type = string
  default = "runner-sg"
}

variable "lb_sg" {
  description = "Load Balancer Security Group"
  type = string
  default = "lb-sg"
}

variable "workers_sg" {
  description = "Worker Nodes Security Group"
  type = string
  default = "workers-sg"
}
