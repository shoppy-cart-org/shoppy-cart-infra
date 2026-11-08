variable "eks_cluster_name" {
  description = "Name of EKS Cluster"
  type        = string
  default     = "sc-eks-cluster"
}

variable "eks_cluster_ng_name" {
  description = "Name of EKS Cluster Node Group"
  type        = string
  default     = "sc-eks-cluster-ng"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.36"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS workers"
  type        = map(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ELB tags only"
  type        = map(string)
}

variable "bastion_sg_id" {
  description = "Bastion Security Group ID (used to access eks api)"
  type        = string
}

variable "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS node IAM role"
  type        = string
}

variable "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI Pod Identity IAM role"
  type        = string
}

variable "bastion_role_arn" {
  description = "ARN of the bastion IAM role (for cluster admin access)"
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS workers"
  type        = string
  default     = "m7i-flex.large"
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 5
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "aws_lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM role (Pod Identity)"
  type        = string
}