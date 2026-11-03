# Bastion SG
resource "aws_security_group" "bastion_sg" {
  name        = var.bastion_sg
  description = "Bastion Security Group"
  vpc_id      = var.vpc_id

  tags = {
    Name = var.bastion_sg
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_myip" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = var.my_ip
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "bastion_allow_all_traffic" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" 
}

# CICD Runner SG
resource "aws_security_group" "runner_sg" {
  name        = var.runner_sg
  description = "Runner Security Group"
  vpc_id      = var.vpc_id

  tags = {
    Name = var.runner_sg
  }
}

resource "aws_vpc_security_group_ingress_rule" "ruuner_ssh_from_bastion" {
  security_group_id = aws_security_group.runner_sg.id
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  referenced_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_vpc_security_group_egress_rule" "runner_allow_all_traffic" {
  security_group_id = aws_security_group.runner_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" 
}

# LB SG
resource "aws_security_group" "lb_sg" {
  name        = var.lb_sg
  description = "Load Balancer Security Group"
  vpc_id      = var.vpc_id

  tags = {
    Name = var.lb_sg
  }
}

resource "aws_vpc_security_group_ingress_rule" "http_traffic" {
  security_group_id = aws_security_group.lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "https_traffic" {
  security_group_id = aws_security_group.lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "lb_allow_to_workers" {
  security_group_id = aws_security_group.lb_sg.id
  referenced_security_group_id = aws_security_group.workers_sg.id
  ip_protocol       = "-1" 
}

# Node Group SG (Workers)
resource "aws_security_group" "workers_sg" {
  name        = var.workers_sg
  description = "Worker Nodes Security Group"
  vpc_id      = var.vpc_id

  tags = {
    Name = var.workers_sg
  }
}

resource "aws_vpc_security_group_ingress_rule" "workers_ssh_from_bastion" {
  security_group_id = aws_security_group.workers_sg.id
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  referenced_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_vpc_security_group_ingress_rule" "traffic_from_lb" {
  security_group_id = aws_security_group.workers_sg.id
  ip_protocol       = "-1"
  referenced_security_group_id = aws_security_group.lb_sg.id
}

resource "aws_vpc_security_group_ingress_rule" "traffic_from_itself" {
  security_group_id = aws_security_group.workers_sg.id
  ip_protocol       = "-1"
  referenced_security_group_id = aws_security_group.workers_sg.id
}

resource "aws_vpc_security_group_egress_rule" "workers_allow_all_traffic" {
  security_group_id = aws_security_group.workers_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" 
}