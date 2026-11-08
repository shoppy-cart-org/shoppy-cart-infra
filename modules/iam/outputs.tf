output "runner_role_arn" {
  description = "ARN of the runner IAM role"
  value       = aws_iam_role.runner_role.arn
}

output "runner_instance_profile_name" {
  description = "Name of the runner instance profile"
  value       = aws_iam_instance_profile.runner_profile.name
}

output "terraform_role_arn" {
  description = "ARN of the Terraform IAM role"
  value       = aws_iam_role.terraform_role.arn
}
output "bastion_role_arn" {
  description = "ARN of the bastion IAM role"
  value       = aws_iam_role.bastion_role.arn
}
output "bastion_instance_profile_name" {
  description = "Name of the bastion instance profile"
  value       = aws_iam_instance_profile.bastion_profile.name
}
output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster_role.arn

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}
output "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = aws_iam_role.eks_node_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_ecr,
    aws_iam_role_policy_attachment.eks_node_cni,
  ]
}
output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI Pod Identity IAM role"
  value       = aws_iam_role.ebs_csi_role.arn

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}

output "aws_lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM role"
  value       = aws_iam_role.aws_lb_controller_role.arn
}