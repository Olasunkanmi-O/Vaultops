
# create a security group for the Jenkins ELB
resource "aws_security_group" "elb_jenkins_sg" {
  name        = "elb-jenkins-external-sg" 
  description = "Security group for Jenkins Classic Load Balancer - public access"
  vpc_id      = aws_vpc.jv-vpc.id

  # Allow inbound HTTP traffic from anywhere 
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access from internet"
  }

  # Allow inbound HTTPS traffic from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS access from internet"
  }

  # Allow all outbound traffic (standard for ELBs to reach instances)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elb-jenkins-sg"
  }
}


# create security group for jenkins
resource "aws_security_group" "jenkins_sg" {
  name_prefix = "jenkins-instance-sg" # Differentiate from ELB SG name
  vpc_id      = aws_vpc.jv-vpc.id

  # Allow outbound traffic (standard for instances needing internet access for updates, SSM, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound traffic for Jenkins web interface (port 8080) ONLY from the Jenkins ELB's security group
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.elb_jenkins_sg.id] # <-- Key Change: Allow from ELB's SG
    description     = "Allow Jenkins UI traffic from ELB"
  }
    
  tags = {
    Name = "jenkins-instance-sg"
  }
}

# create jenkins instance 
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "jenkins-server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.pri_sub1.id
  availability_zone           = aws_subnet.pri_sub1.availability_zone 
  #associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id] 
  iam_instance_profile        = aws_iam_instance_profile.jenkins_instance_profile.name
  user_data                   = file("jenkins_userdata.sh")
  root_block_device {
    volume_size = 20    # Size in GB
    volume_type = "gp3" # General Purpose SSD (recommended)
    encrypted   = true  # Enable encryption (best practice)
  }
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "jenkins-server"
  }
}

# Jenkins IAM role 
resource "aws_iam_role" "jenkins_ssm_role" {
  name = "jenkins_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

# Administrative access for jenkins
resource "aws_iam_role_policy_attachment" "jenkins_admin_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"  
  role       = aws_iam_role.jenkins_ssm_role.name
}

# SSM policy attachment for jenkins 
resource "aws_iam_role_policy_attachment" "jenkins_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"  
  role       = aws_iam_role.jenkins_ssm_role.name
}

# CREATE INSTANCE PROFILE FOR JENKINS SERVER
resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  name = "jenkins-profile"
  role = aws_iam_role.jenkins_ssm_role.name
}

# # create hosted zone
# resource "aws_route53_zone" "public_zone" {
#   name = var.domain_name 
# }

data "aws_route53_zone" "public_zone" {
  name         = var.domain_name
  private_zone = false
}

# acm certificate 
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method = "DNS"
  tags = {
    Name = "acm-cert"
  }
  lifecycle {
    create_before_destroy = true
  }
}



# create DNS validation record
resource "aws_route53_record" "acm_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
    }
    
  }
  zone_id = data.aws_route53_zone.public_zone.id
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
}

# Create elastic Load Balancer for Jenkins
resource "aws_elb" "elb_jenkins" {
  name                = "elb-jenkins"
  security_groups     = [aws_security_group.elb_jenkins_sg.id] 
  subnets             = [aws_subnet.pub_sub1.id]

  listener {
    instance_port      = 8080
    instance_protocol  = "HTTP"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = aws_acm_certificate.cert.arn
  }
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    target              = "TCP:8080" # Consider HTTP:8080/login or similar for better health check
  }
  instances                   = [aws_instance.jenkins-server.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
  tags = {
    Name = "jenkins-server"
  }

  depends_on = [ aws_acm_certificate_validation.cert_validation ]
}

# Create Route 53 record for jenkins server
resource "aws_route53_record" "jenkins" {
  zone_id = data.aws_route53_zone.public_zone.id
  name    = "jenkins.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_elb.elb_jenkins.dns_name
    zone_id                = aws_elb.elb_jenkins.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for k, record in aws_route53_record.acm_validation_record : record.fqdn]

  depends_on = [aws_route53_record.acm_validation_record]
}