terraform {
  backend "s3" {
    bucket       = "shoppy-cart-s3-terraform-state"
    key          = "environments/dev/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}