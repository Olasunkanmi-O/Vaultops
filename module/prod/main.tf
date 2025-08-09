#prod security group
resource "aws_security_group" "prod-sg" {
  name        = "app-prod-sg"
  description = "prod Security group"
  vpc_id      = var.vpc_id
  ingress {
    description     = "SSH access from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg, var.ansible_sg]
  }

  ingress {
    description     = "HTTP access from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.prod-alb-sg.id]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "app-prod-sg"
  }
}

# security group for ALB prod
resource "aws_security_group" "prod-alb-sg" {
  name        = "app-prod-alb-sg"
  description = "prod-alb Security group"
  vpc_id      = var.vpc_id
  ingress {
    description = "HTTPs access from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "app-prod-elb-sg"
  }
}

# IAM Role for prod EC2 Instances
resource "aws_iam_role" "prod_app_role" {
  name_prefix        = "prod-app-role-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "prod-app-role"
  }
}

# Attach AmazonSSMManagedInstanceCore policy
resource "aws_iam_role_policy_attachment" "prod_ssm_managed_policy_attach" {
  role       = aws_iam_role.prod_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Define a custom IAM Policy for prod Apps (for Vault access)
resource "aws_iam_policy" "prod_app_custom_policy" {
  name_prefix = "prod-app-custom-policy-"
  description = "Custom policy for prod Application EC2 Servers"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # --- Permissions for Vault AWS Auth Method ---
      {
        Effect   = "Allow",
        Action   = "sts:GetCallerIdentity",
        Resource = "*", # Essential for Vault's AWS Auth method
      },
      # --- Permission to read prod Database secrets from Vault KV ---
      {
        Effect = "Allow",
        Action = [
          "vault:read"
        ],
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*", # Placeholder, Vault policy resource is on Vault server
        # The above 'Resource' for Vault policies in AWS IAM is not actually how Vault policies work.
        # This is a common point of confusion. The IAM policy simply says "this EC2 can talk to STS for Vault".
        # The 'database-prod-read' policy is defined *within Vault itself* and restricts access to the KV path.
        # The 'vault:read' action is NOT an AWS IAM action, it's a conceptual Vault permission.
        # You DON'T put vault-specific resource ARNs in AWS IAM policies.
        # So, the 'Resource' should typically be for actual AWS resources.
        # For simplicity, if you're only granting specific Vault-related AWS actions, it's usually just sts:GetCallerIdentity.

        # Corrected:
        # If your application needs to fetch secrets from Vault, the IAM policy attached
        # to its role primarily needs sts:GetCallerIdentity to authenticate with Vault.
        # The access to specific secrets (kv/database/prod/pet-db) is then controlled
        # by the *Vault policy* (database-prod-read) attached to the Vault AWS Auth Role.
        # So, typically, this custom IAM policy would mainly contain sts:GetCallerIdentity.
      },
      # --- S3 Read Access for Application Code (if fetched from S3) ---
      # Example: If your app fetches config/code from S3, add permissions here.
      # {
      #   Effect   = "Allow",
      #   Action   = [
      #     "s3:GetObject",
      #     "s3:ListBucket"
      #   ],
      #   Resource = [
      #     "arn:aws:s3:::your-app-code-bucket",
      #     "arn:aws:s3:::your-app-code-bucket/*"
      #   ],
      # },
    ]
  })
}

# Attach the custom policy to the role
resource "aws_iam_role_policy_attachment" "prod_app_custom_policy_attach" {
  role       = aws_iam_role.prod_app_role.name
  policy_arn = aws_iam_policy.prod_app_custom_policy.arn
}

# IAM Instance Profile for prod EC2 Instances
resource "aws_iam_instance_profile" "prod_instance_profile" {
  name_prefix = "prod-app-profile-"
  role        = aws_iam_role.prod_app_role.name

  tags = {
    Name = "prod-app-profile"
  }
}

# Data source to get current AWS account ID for ARN construction
data "aws_caller_identity" "current" {}

# Data source to get the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# launch template
resource "aws_launch_template" "prod_launch_template" {
  name_prefix   = "prod"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.prod_instance_profile.name
  }
  user_data = base64encode(file("${path.module}/../common_assets/user_data/asg_userdata.sh"))
  network_interfaces {
    security_groups       = [aws_security_group.prod-sg.id]
    delete_on_termination = true
  }
  metadata_options {
    http_tokens = "required"
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "DockerHost"
      Environment = var.environment # e.g., "prod" or "production"
      Role        = "docker-host"   # Important for Ansible dynamic inventory
      Project     = "JenkinsVault"  # Important for Ansible dynamic inventory
    }
  }

}

#Create Target group for load Balancer
resource "aws_lb_target_group" "prod_target_group" {
  name     = "app-prod-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    path                = "/"
  }
  tags = {
    Name = "app-prod-tg"
  }
}

# create autoscaling group for prod
resource "aws_autoscaling_group" "prod_autoscaling_group" {
  name                      = "prod_autoscaling_group"
  max_size                  = 2
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 2
  force_delete              = true
  launch_template {
    id      = aws_launch_template.prod_launch_template.id
    version = "$Latest"
  }
  vpc_zone_identifier = [var.pri_sub1, var.pri_sub2]
  target_group_arns   = [aws_lb_target_group.prod_target_group.arn]

  instance_maintenance_policy {
    min_healthy_percentage = 90
    max_healthy_percentage = 120
  }
  tag {
    key                 = "Name"
    value               = "app-prod-server"
    propagate_at_launch = true
  }
}

# Create ASG policy for prod
resource "aws_autoscaling_policy" "prod-asg-policy" {
  name                   = "app-prod-asg-policy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.prod_autoscaling_group.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# create ALB for prod 
resource "aws_lb" "prod_alb" {
  name               = "app-prod-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod-alb-sg.id]
  subnets            = [var.pub_sub1, var.pub_sub2]

  tags = {
    Name = "app-prod-lb"
  }
}

# Create load balance listener for http
resource "aws_lb_listener" "prod_lb_listener_http" {
  load_balancer_arn = aws_lb.prod_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_target_group.arn
  }
}
# Create load balance listener for https
resource "aws_lb_listener" "prod_lb_listener_https" {
  load_balancer_arn = aws_lb.prod_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_cert_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_target_group.arn
  }
}



# Create Route 53 record for prod server
resource "aws_route53_record" "prod-record" {
  zone_id = var.route_53_zone_id
  name    = "prod.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_lb.prod_alb.dns_name
    zone_id                = aws_lb.prod_alb.zone_id
    evaluate_target_health = true
  }
}