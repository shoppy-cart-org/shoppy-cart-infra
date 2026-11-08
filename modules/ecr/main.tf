resource "aws_ecr_repository" "service" {
  for_each = var.service_names

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.project_name}-${each.value}"
      Project   = var.project_name
      Service   = each.value
      ManagedBy = "Terraform"
    }
  )
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain the latest ${var.image_retention_count} Git-tagged images."

        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["git-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.image_retention_count
        }

        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after ${var.untagged_image_retention_days} days."

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}