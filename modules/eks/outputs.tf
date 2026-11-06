output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.my_eks.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.my_eks.endpoint
}

output "node_group_name" {
  description = "Name of the EKS node group"
  value       = aws_eks_node_group.my_eks_ng.node_group_name
}