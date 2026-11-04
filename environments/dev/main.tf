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

  tags = local.common_tags
}