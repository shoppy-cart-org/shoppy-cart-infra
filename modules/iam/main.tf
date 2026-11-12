# Runner Role
resource "aws_iam_role" "runner_role" {
  name = var.runner_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

#Terraform Role
resource "aws_iam_role" "terraform_role" {
  name = var.terraform_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.runner_role.arn
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# Runner Instance Profile
resource "aws_iam_instance_profile" "runner_profile" {
  name = var.runner_profile_name
  role = aws_iam_role.runner_role.name
}

# Runner Permissions Policy (templatefile)
resource "aws_iam_policy" "runner_policy" {
  name        = var.runner_policy_name
  description = "Allows the self-hosted runner to assume the Terraform IAM role."

  policy = templatefile("${path.module}/policies/runner-policy.json.tftpl", {
    terraform_role_arn = aws_iam_role.terraform_role.arn
  })
}

# Attach Runner Policy to Runner Role
resource "aws_iam_role_policy_attachment" "runner_policy_attachment" {
  role       = aws_iam_role.runner_role.name
  policy_arn = aws_iam_policy.runner_policy.arn
}


# Terraform Policy (templatefile)
resource "aws_iam_policy" "terraform_policy" {
  name        = var.terraform_policy_name
  description = "Permissions for Terraform to manage Shoppy Cart infrastructure."

  policy = templatefile("${path.module}/policies/terraform-policy.json.tftpl", {
    terraform_state_bucket = var.terraform_state_bucket
    terraform_state_key    = var.terraform_state_key
  })
}

# Attach Terraform Policy to Terraform Role
resource "aws_iam_role_policy_attachment" "terraform_policy_attachment" {
  role       = aws_iam_role.terraform_role.name
  policy_arn = aws_iam_policy.terraform_policy.arn
}

# ── Bastion Role ──
resource "aws_iam_role" "bastion_role" {
  name = var.bastion_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = {
    Name = var.bastion_role_name
  }
}

# ── Bastion Policy ──
resource "aws_iam_policy" "bastion_policy" {
  name        = var.bastion_policy_name
  description = "Minimal permissions for the bastion: EKS describe only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSReadOnly"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
  tags = {
    Name = var.bastion_policy_name
  }
}

# ── Attach Bastion Policy ──
resource "aws_iam_role_policy_attachment" "bastion_policy_attachment" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = aws_iam_policy.bastion_policy.arn
}

# ── Bastion Instance Profile ──
resource "aws_iam_instance_profile" "bastion_profile" {
  name = var.bastion_profile_name
  role = aws_iam_role.bastion_role.name

  tags = {
    Name = var.bastion_profile_name
  }
}


# EKS CLUSTER ROLE
resource "aws_iam_role" "eks_cluster_role" {
  name = var.eks_cluster_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = var.eks_cluster_role_name }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# EKS NODE ROLE
resource "aws_iam_role" "eks_node_role" {
  name = var.eks_node_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = var.eks_node_role_name }
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}
resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# EBS CSI POD IDENTITY ROLE
resource "aws_iam_role" "ebs_csi_role" {
  name = var.ebs_csi_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = { Name = var.ebs_csi_role_name }
}
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── AWS Load Balancer Controller Role (Pod Identity) ──
resource "aws_iam_role" "aws_lb_controller_role" {
  name = var.aws_lb_controller_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = { Name = var.aws_lb_controller_role_name }
}

# ── AWS Load Balancer Controller Policy ──
resource "aws_iam_policy" "aws_lb_controller_policy" {
  name        = var.aws_lb_controller_policy_name
  description = "Permissions for AWS Load Balancer Controller"

  policy = file("${path.module}/policies/aws-lb-controller-policy.json.tftpl")

  tags = { Name = var.aws_lb_controller_policy_name }
}

# ── Attach Policy to Role ──
resource "aws_iam_role_policy_attachment" "aws_lb_controller_policy_associate" {
  role       = aws_iam_role.aws_lb_controller_role.name
  policy_arn = aws_iam_policy.aws_lb_controller_policy.arn
}

# ── ExternalDNS Role (Pod Identity) ──
resource "aws_iam_role" "external_dns_role" {
  name = "ScExternalDnsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = { Name = "ScExternalDnsRole" }
}

resource "aws_iam_policy" "external_dns_policy" {
  name        = "sc-external-dns-policy"
  description = "Route53 permissions for ExternalDNS"

  policy = file("${path.module}/policies/external-dns-policy.json.tftpl")

  tags = { Name = "sc-external-dns-policy" }
}

resource "aws_iam_role_policy_attachment" "external_dns_associate" {
  role       = aws_iam_role.external_dns_role.name
  policy_arn = aws_iam_policy.external_dns_policy.arn
}

# ── App CI Role (ECR push only) ──
resource "aws_iam_role" "app_ci_role" {
  name = "ScAppCiRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.runner_role.arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = { Name = "ScAppCiRole" }
}

resource "aws_iam_policy" "app_ci_policy" {
  name        = "sc-app-ci-policy"
  description = "ECR push permissions for app CI"

  policy = file("${path.module}/policies/app-ci-policy.json.tftpl")

  tags = { Name = "sc-app-ci-policy" }
}

resource "aws_iam_role_policy_attachment" "app_ci_associate" {
  role       = aws_iam_role.app_ci_role.name
  policy_arn = aws_iam_policy.app_ci_policy.arn
}