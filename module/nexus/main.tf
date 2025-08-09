
# Creating security group for Nexus
resource "aws_security_group" "Nexus-sg" {
  name        = "app-Nexus-sg"
  description = "Allow inbound traffic from lb and all outbound traffic"
  vpc_id      = var.vpc_id

  # Ingress rule: Allow Nexus port (port 8081) from loadbalancer sg
  ingress {
    description     = "Nexus (port 8081)"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-sg.id]
  }

  ingress {
    description = "custom (port 8085)"
    from_port   = 8085
    to_port     = 8085
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress rule: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # All protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound to anywhere
  }

  tags = {
    Name = "app-Nexus-sg"
  }
}

# Creating security group for LoadBalancer
resource "aws_security_group" "lb-sg" {
  name        = "app-lb-sg"
  description = "Allow inbound traffic for lb and all outbound traffic"
  vpc_id      = var.vpc_id


  # Ingress rule: Allow HTTPS (port 443) from within VPC
  ingress {
    description = "HTTPS (port 443)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow from the VPC CIDR block
  }

  # Egress rule: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # All protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound to anywhere
  }

  tags = {
    Name = "app-lb-sg"
  }
}
# create loadbalancer for the nexus
resource "aws_elb" "elb_nexus" {
  name            = "app-nexus-elb"
  security_groups = [aws_security_group.lb-sg.id]
  subnets         = [var.pub_sub1_id, var.pub_sub2_id]

  listener {
    instance_port      = 8081
    instance_protocol  = "HTTP"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = var.certificate
  }
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    target              = "TCP:8081"
  }
  instances                   = [aws_instance.Nexus-server.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
  tags = {
    Name = "app-nexus-elb"
  }
}

# Create a DNS record for the ELB
resource "aws_route53_record" "nexus" {
  zone_id = var.hosted_zone_id
  name    = "nexus.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_elb.elb_nexus.dns_name
    zone_id                = aws_elb.elb_nexus.zone_id
    evaluate_target_health = true
  }
}
# create an IAM instance role
resource "aws_iam_role" "nexus-role" {
  name = "app-nexus-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "app-nexus-role"
  }
}

# nexus IAM profile
resource "aws_iam_instance_profile" "nexus_profile" {
  name = "app-nexus-profile"
  role = aws_iam_role.nexus-role.name
}

# SSM permission
resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.nexus-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# Data source to get the latest red-hat AMI
data "aws_ami" "centos" {
  most_recent = true
  owners      = ["125523088429"] # Verified CentOS image owner (check regionally!)

  filter {
    name   = "name"
    values = ["CentOS Stream 9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create Nexus Server
resource "aws_instance" "Nexus-server" {
  ami                    = data.aws_ami.centos.id #centOs stream_9
  instance_type          = "t3.medium"
  vpc_security_group_ids = [aws_security_group.Nexus-sg.id]
  #key_name                    = var.keypair
  subnet_id                   = var.pub_sub2_id
  user_data                   = file("${path.module}/nexus_userdata.sh")
  iam_instance_profile        = aws_iam_instance_profile.nexus_profile.name
  associate_public_ip_address = true


  tags = {
    Name = "app-nexus-server"
  }
}
# resource "null_resource" "update_jenkins" {
#   depends_on = [aws_instance.Nexus-server]

#   provisioner "local-exec" {
#     command = <<-EOF
# #!/bin/bash
# sudo cat <<EOT>> /etc/docker/daemon.json
#   {
#     "insecure-registries" : ["${aws_instance.Nexus-server.public_ip}:8085"]
#   }
# EOT
# sudo systemctl restart docker
# EOF
#   interpreter = [ "bash", "-c" ]
#   } 
# }