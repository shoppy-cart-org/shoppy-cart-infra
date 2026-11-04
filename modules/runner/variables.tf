variable "private_subnet_id" {
  description = "Private subnet ID for the runner EC2"
  type        = string
}

variable "runner_sg_id" {
  description = "Security group ID for the runner"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name (sc-runner-instance-profile)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the runner"
  type        = string
  default     = "m7i-flex.large"
}

variable "instance_name" {
  description = "Runner Instance Name"
  type = string
  default = "sc-runner"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}