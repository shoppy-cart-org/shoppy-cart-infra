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
      Action = "sts:AssumeRole"
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
      Action = "sts:AssumeRole"
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