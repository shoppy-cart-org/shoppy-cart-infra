variable "bastion_key_name" {
  description = "Bastion Key Name"
  type = string
  default = "sc-bastion-keypair"
}

variable "runner_key_name" {
  description = "Runner Key Name"
  type = string
  default = "sc-runner-keypair"
}

variable "bastion_public_key_path" {
  description = "Path to the bastion public key"
  type        = string
  default     = "~/.ssh/sc-bastion-keypair.pub"
}

variable "runner_public_key_path" {
  description = "Path to the runner public key"
  type        = string
  default     = "~/.ssh/sc-runner-keypair.pub"
}
