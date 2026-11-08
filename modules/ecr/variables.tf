variable "project_name" {
  description = "Project name used as the ECR repository namespace."
  type        = string
}

variable "service_names" {
  description = "Names of the microservices that need ECR repositories."
  type        = set(string)
}

variable "image_retention_count" {
  description = "Number of Git-tagged images to retain per repository."
  type        = number
  default     = 30

  validation {
    condition     = var.image_retention_count >= 1
    error_message = "image_retention_count must be at least 1."
  }
}

variable "untagged_image_retention_days" {
  description = "Number of days before untagged images expire."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_image_retention_days >= 1
    error_message = "untagged_image_retention_days must be at least 1."
  }
}

variable "tags" {
  description = "Tags applied to ECR repositories."
  type        = map(string)
  default     = {}
}