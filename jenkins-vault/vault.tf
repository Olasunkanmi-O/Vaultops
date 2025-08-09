# Data block to fetch details about the AWS account
data "aws_caller_identity" "current" {}

# Data to get the name of the S3 bucket to use for vault 
data "aws_s3_bucket" "shared_bucket_data" {
  bucket = var.vault_storage # References the name from the variable
}

# Create security group for vault ELB
resource "aws_security_group" "elb_vault_sg" {
  name        = "elb-vault-external-sg"
  description = "Security group for Vault Classic Load Balancer - public access"
  vpc_id      = aws_vpc.jv-vpc.id

  # Allow inbound HTTP traffic from anywhere (for redirect to HTTPS)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access from internet"
  }

  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access from other resources to fetch credentials"
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
    Name = "elb-vault-sg"
  }
}

# Create security group for vault instance
resource "aws_security_group" "vault_sg" {
  name_prefix = "vault-instance-sg"
  description = "Security group for Vault instances"
  vpc_id      = aws_vpc.jv-vpc.id

  # Allow outbound traffic (for updates, SSM, S3, KMS, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound traffic for Vault web interface (port 8200) ONLY from the ELB security group
  ingress {
    from_port       = 8200
    to_port         = 8200
    protocol        = "tcp"
    security_groups = [aws_security_group.elb_vault_sg.id]
    description     = "Allow Vault UI traffic from ELB"
  }
  
  tags = {
    Name = "vault-instance-sg"
  }
}

# KMS Key for Vault Auto-Unseal
resource "aws_kms_key" "vault_auto_unseal_key" {
  description             = "KMS key for Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Vault to use the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.vault_server_role.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "vault-auto-unseal-key"
  }
}

# Alias for the KMS key (for easier reference)
resource "aws_kms_alias" "vault_auto_unseal_key_alias" {
  name          = var.vault_kms_key_alias
  target_key_id = aws_kms_key.vault_auto_unseal_key.key_id
}

# IAM Role for Vault Server
resource "aws_iam_role" "vault_server_role" {
  name_prefix = "vault-server-role-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "vault-server-role"
  }
}

# IAM Policy for Vault Server (S3 backend & KMS auto-unseal)
resource "aws_iam_policy" "vault_server_policy" {
  name_prefix = "vault-server-policy-"
  description = "Policy for Vault server with S3 backend and KMS auto-unseal"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permissions for S3 storage backend
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          data.aws_s3_bucket.shared_bucket_data.arn,
          "${data.aws_s3_bucket.shared_bucket_data.arn}/*"
        ]
      },
      # Permissions for KMS auto-unseal
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.vault_auto_unseal_key.arn
      },
      # Permissions for SSM Agent to function
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach custom policy to role
resource "aws_iam_role_policy_attachment" "vault_server_policy_attach" {
  role       = aws_iam_role.vault_server_role.name
  policy_arn = aws_iam_policy.vault_server_policy.arn
}

# SSM policy attachment for vault 
resource "aws_iam_role_policy_attachment" "vault_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.vault_server_role.name
}

# Create instance profile for vault server
resource "aws_iam_instance_profile" "vault_instance_profile" {
  name = "vault-profile"
  role = aws_iam_role.vault_server_role.name
}

# Create vault instance 
resource "aws_instance" "vault-server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  #associate_public_ip_address = true
  subnet_id                   = aws_subnet.pri_sub1.id
  availability_zone           = aws_subnet.pri_sub1.availability_zone
  vpc_security_group_ids      = [aws_security_group.vault_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_instance_profile.name
  user_data                   = templatefile("vault_userdata.sh", {
    vault_storage = var.vault_storage
    vault_region  = var.vault_region
    kms_key_id    = aws_kms_key.vault_auto_unseal_key.id
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "vault-server"
  }
}

# Create Elastic Load Balancer for vault
resource "aws_elb" "elb_vault" {
  name            = "elb-vault"
  security_groups = [aws_security_group.elb_vault_sg.id]
  # Multi-AZ deployment - make sure you have pub_sub2 defined
  subnets = [aws_subnet.pub_sub1.id]

  # HTTP listener (for potential redirect to HTTPS)
  listener {
    instance_port     = 8200
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  # HTTPS listener
  listener {
    instance_port      = 8200
    instance_protocol  = "HTTP"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = aws_acm_certificate.cert.arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    target              = "HTTP:8200/v1/sys/health"
  }

  instances                   = [aws_instance.vault-server.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "vault-elb"
  }

  depends_on = [aws_acm_certificate_validation.cert_validation]
}

# Create Route 53 record for vault server
resource "aws_route53_record" "vault-record" {
  zone_id = data.aws_route53_zone.public_zone.id
  name    = "vault.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_elb.elb_vault.dns_name
    zone_id                = aws_elb.elb_vault.zone_id
    evaluate_target_health = true
  }
}




