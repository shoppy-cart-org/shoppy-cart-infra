variable "bastion_key_name" {
  description = "Bastion Key Name"
  type        = string
  default     = "sc-bastion-keypair"
}

variable "runner_key_name" {
  description = "Runner Key Name"
  type        = string
  default     = "sc-runner-keypair"
}

variable "bastion_public_key" {
  description = "Bastion public key"
  type        = string
}

variable "runner_public_key" {
  description = "Runner public key"
  type        = string
}
