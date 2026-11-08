module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr = var.vpc_cidr
  vpc_name = var.vpc_name
  igw_name = var.igw_name

  tags = local.common_tags
}
module "security-groups" {
  source = "../../modules/security-groups"

  vpc_id = module.vpc.vpc_id
  my_ip  = var.my_ip
}

module "iam" {
  source = "../../modules/iam"

  terraform_state_bucket = var.terraform_state_bucket
  terraform_state_key    = var.terraform_state_key
}

module "runner" {
  source = "../../modules/runner"

  private_subnet_id     = module.vpc.private_app_subnet_ids["private-app-sub-1"]
  runner_sg_id          = module.security-groups.runner_sg_id
  instance_profile_name = module.iam.runner_instance_profile_name
  runner_key_name       = module.keypair.runner_key_name

  tags = local.common_tags
}

module "keypair" {
  source = "../../modules/keypair"

  bastion_public_key = var.bastion_public_key
  runner_public_key  = var.runner_public_key
}

module "bastion" {
  source = "../../modules/bastion"

  public_subnet_id      = module.vpc.public_subnet_ids["public-sub-1"]
  bastion_sg_id         = module.security-groups.bastion_sg_id
  instance_profile_name = module.iam.bastion_instance_profile_name
  bastion_key_name      = module.keypair.bastion_key_name

  tags = local.common_tags

}

module "eks" {
  source = "../../modules/eks"

  private_subnet_ids         = module.vpc.private_app_subnet_ids
  public_subnet_ids          = module.vpc.public_subnet_ids
  cluster_role_arn           = module.iam.eks_cluster_role_arn
  node_role_arn              = module.iam.eks_node_role_arn
  ebs_csi_role_arn           = module.iam.ebs_csi_role_arn
  bastion_role_arn           = module.iam.bastion_role_arn
  bastion_sg_id              = module.security-groups.bastion_sg_id
  aws_lb_controller_role_arn = module.iam.aws_lb_controller_role_arn

  tags = local.common_tags
}


module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name

  service_names = toset([
    "adservice",
    "cartservice",
    "checkoutservice",
    "currencyservice",
    "emailservice",
    "frontend",
    "loadgenerator",
    "paymentservice",
    "productcatalogservice",
    "recommendationservice",
    "shippingservice",
    "shoppingassistantservice"
  ])

  image_retention_count         = 30
  untagged_image_retention_days = 7

  depends_on = [module.iam]
}