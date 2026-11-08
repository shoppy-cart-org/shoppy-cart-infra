variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "igw_name" {
  description = "Internet Gateway name"
  type        = string
}

variable "my_ip" {
  description = "My IP Address"
  type        = string
  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && endswith(var.my_ip, "/32")
    error_message = "my_ip must be a valid /32 CIDR (e.g., 1.2.3.4/32)."
  }
}
variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state"
  type        = string
}
variable "terraform_state_key" {
  description = "S3 key (path) for the Terraform state file"
  type        = string
}

variable "runner_public_key" {
  description = "Runner EC2 public key content"
  type        = string
}

variable "bastion_public_key" {
  description = "Bastion EC2 public key content"
  type        = string
}

variable "project_name" {
  description = "Project name used as the ECR repository namespace."
  type        = string
}