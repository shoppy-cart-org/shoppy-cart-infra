# EKS CLUSTER
resource "aws_eks_cluster" "my_eks" {
  name     = var.eks_cluster_name
  version  = var.cluster_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = values(var.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  tags = merge(var.tags, { Name = var.eks_cluster_name })

}

# Allow bastion to reach the EKS API server
resource "aws_vpc_security_group_ingress_rule" "eks_api_from_bastion" {
  security_group_id            = aws_eks_cluster.my_eks.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = var.bastion_sg_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Allow bastion to reach EKS API"
}

# EKS MANAGED NODE GROUP (3 nodes, one per AZ)
resource "aws_eks_node_group" "my_eks_ng" {
  cluster_name    = aws_eks_cluster.my_eks.name
  node_group_name = var.eks_cluster_ng_name
  node_role_arn   = var.node_role_arn
  subnet_ids      = values(var.private_subnet_ids)

  instance_types = [var.node_instance_type]
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  tags = merge(var.tags, { Name = var.eks_cluster_ng_name })
}

# Tag the node group's EC2 instances with a static Name
resource "aws_autoscaling_group_tag" "nodes_name_tag" {
  autoscaling_group_name = aws_eks_node_group.my_eks_ng.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "Name"
    value               = "sc-worker-node"
    propagate_at_launch = true
  }
}

# EKS ADDONS
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.my_eks.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.my_eks.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.my_eks.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.my_eks.name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    role_arn        = var.ebs_csi_role_arn
    service_account = "ebs-csi-controller-sa"
  }

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.my_eks.name
  addon_name   = "eks-pod-identity-agent"
}

# BASTION ACCESS ENTRY + ADMIN POLICY
resource "aws_eks_access_entry" "bastion_admin" {
  cluster_name  = aws_eks_cluster.my_eks.name
  principal_arn = var.bastion_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion_admin_associate" {
  cluster_name  = aws_eks_cluster.my_eks.name
  principal_arn = var.bastion_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion_admin]
}

# ── AWS Load Balancer Controller Pod Identity Association ──
resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  cluster_name    = aws_eks_cluster.my_eks.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = var.aws_lb_controller_role_arn
}

# ── ExternalDNS Pod Identity Association ──
resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = aws_eks_cluster.my_eks.name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = var.external_dns_role_arn
}