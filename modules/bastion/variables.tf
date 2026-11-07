variable "public_subnet_id" {
  description = "Public subnet ID for the bastion"
  type        = string
}

variable "bastion_name" {
  description = "Bastion EC2 Name"
  type        = string
  default     = "sc-bastion"
}

variable "bastion_sg_id" {
  description = "Security group ID for the bastion"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name (sc-bastion-instance-profile)"
  type        = string
}

variable "bastion_key_name" {
  description = "SSH key pair name (sc-bastion-keypair)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}