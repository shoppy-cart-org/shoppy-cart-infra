# Bastion Keypair
resource "aws_key_pair" "bastion_keypair" {
  key_name   = var.bastion_key_name
  public_key = file(pathexpand(var.bastion_public_key_path))

  tags = {
    Name = var.bastion_key_name
  }
}

# Runner Keypair
resource "aws_key_pair" "runner_keypair" {
  key_name   = var.runner_key_name
  public_key = file(pathexpand(var.runner_public_key_path))

  tags = { 
    Name = var.runner_key_name
  }
}