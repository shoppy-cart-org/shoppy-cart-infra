variable "vpc_cidr" {
  description = "VPC CIDR Block"
  type        = string
}

variable "vpc_name" {
  description = "VPC Name"
  type        = string
}

variable "tags" {
  description = "Common Tags (project name, env etc..)"
  type        = map(string)
  default     = {}
}

variable "public_sub_cidr" {
  description = "Public Subnet CIDR Block with Az"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "public-sub-1" = { cidr = "10.70.1.0/24", az = "eu-north-1a" },
    "public-sub-2" = { cidr = "10.70.2.0/24", az = "eu-north-1b" },
    "public-sub-3" = { cidr = "10.70.3.0/24", az = "eu-north-1c" },
  }
}

variable "private_app_sub_cidr" {
  description = "Private App Subnet CIDR Block with Az"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "private-app-sub-1" = { cidr = "10.70.21.0/24", az = "eu-north-1a" },
    "private-app-sub-2" = { cidr = "10.70.22.0/24", az = "eu-north-1b" },
    "private-app-sub-3" = { cidr = "10.70.23.0/24", az = "eu-north-1c" },
  }
}

variable "private_data_sub_cidr" {
  description = "Private Data Subnet CIDR Block with Az"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "private-data-sub-1" = { cidr = "10.70.41.0/24", az = "eu-north-1a" },
    "private-data-sub-2" = { cidr = "10.70.42.0/24", az = "eu-north-1b" },
    "private-data-sub-3" = { cidr = "10.70.43.0/24", az = "eu-north-1c" },
  }
}

variable "igw_name" {
  description = "Internet Gateway Name"
  type        = string
}