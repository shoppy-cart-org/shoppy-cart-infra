terraform {
  backend "s3" {
    bucket       = "shoppy-cart-terraform-state-emson"
    key          = "environments/dev/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}