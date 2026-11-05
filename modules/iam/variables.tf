variable "runner_role_name" {
  description = "Name of the IAM role assigned to the self-hosted runner."
  type = string
  default = "ScRunnerRole"
}

variable "runner_profile_name" {
  description = "Name of the EC2 instance profile associated with the runner IAM role."
  type = string
  default = "sc-runner-instance-profile"
}

variable "terraform_role_name" {
  description = "Name of the IAM role assumed by Terraform workflows to manage AWS infrastructure."
  type = string
  default = "ScTerraformRole"
}

variable "runner_policy_name" {
  description = "Name of the IAM policy allowing the runner to assume the Terraform IAM role."
  type = string
  default = "sc-runner-policy"
}

variable "terraform_policy_name" {
  description = "Name of the IAM policy granting Terraform permissions to manage AWS infrastructure."
  type = string
  default = "sc-terraform-policy"
}

variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state"
  type        = string
}

variable "terraform_state_key" {
  description = "S3 key (path) for the Terraform state file"
  type        = string
}

variable "bastion_role_name" {
  description = "Name of the bastion IAM role"
  type        = string
  default     = "ScBastionRole"
}

variable "bastion_policy_name" {
  description = "Name of the bastion IAM policy"
  type        = string
  default     = "sc-bastion-policy"
}

variable "bastion_profile_name" {
  description = "Name of the bastion instance profile"
  type        = string
  default     = "sc-bastion-instance-profile"
}