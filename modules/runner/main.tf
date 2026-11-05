# Fetch latest official Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Combine the runner installation scripts (using cloud-init)
data "cloudinit_config" "runner_config" {
  gzip          = true
  base64_encode = true

  # First script
  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/scripts/install-tools.sh")
    filename     = "install-tools.sh"
  }

  # Second script
  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/scripts/install-runner.sh")
    filename     = "install-runner.sh"
  }

   # 3. Copy the registration script to disk (manual step)
  part {
    content_type = "text/cloud-config"
    filename     = "write-register-script.yaml"
    content = yamlencode({
      write_files = [
        {
          path        = "/home/ubuntu/register-runner.sh"
          permissions = "0755"
          owner       = "ubuntu:ubuntu"
          content     = file("${path.module}/scripts/register-runner.sh")
        }
      ]
    })
  }
}

# Runner EC2
resource "aws_instance" "runner_ec2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = var.private_subnet_id
  vpc_security_group_ids = [var.runner_sg_id]
  iam_instance_profile   = var.instance_profile_name
  key_name = var.runner_key_name
  associate_public_ip_address = false

  user_data_base64  = data.cloudinit_config.runner_config.rendered

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted = true
  }


  tags = merge(
    var.tags,
    {Name= var.instance_name}
  )

}
