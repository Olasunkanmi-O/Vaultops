# Data source to get the latest RedHat AMI
data "aws_ami" "redhat" {
  most_recent = true
  owners      = ["309956199498"] # RedHat's owner ID
  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Create Ansible Server EC2 Instance
resource "aws_instance" "ansible-server" {
  ami                    = data.aws_ami.redhat.id # Ensure this resolves to a valid Red Hat AMI
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.ansible_instance_profile.name # Referencing the correct instance profile name
  vpc_security_group_ids = [aws_security_group.ansible-sg.id] # Ensure this SG allows necessary traffic
  subnet_id              = var.pri_sub2_id
  user_data = templatefile("${path.module}/ansible_userdata.sh.tpl", {
    # Use the Terraform input variable for the dynamic IP
    vault_server_private_ip = var.vault_server_private_ip,
    VAULT_ZIP               = "vault_1.16.2_linux_amd64.zip"
    # Hardcode VAULT_VERSION here, as it's not a Terraform input variable in this scenario
    VAULT_VERSION           = "1.16.2" # Fixed value passed to the template
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
    Name = "app-ansible-server"
  }
}

#Creating ansible security group
resource "aws_security_group" "ansible-sg" {
  name        = "app-ansible-sg"
  description = "Allow ssh"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ssh port"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "app-ansible-sg"
  }
}

# Create IAM role for ansible
resource "aws_iam_role" "ansible_role" { # Renamed to follow convention: resource_type.name_of_resource
  name_prefix        = "ansible-server-role-" # Use name_prefix for unique names
  description        = "IAM Role for Ansible EC2 Server"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
    }]
  })

  tags = {
    Name = "ansible-server-role"
  }
}

# Define a custom IAM Policy for Ansible Server's specific needs
resource "aws_iam_policy" "ansible_custom_policy" {
  name_prefix = "ansible-server-custom-policy-"
  description = "Custom policy for Ansible EC2 Server"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # --- Permissions for Vault AWS Auth Method ---
      {
        Effect   = "Allow",
        Action   = "sts:GetCallerIdentity",
        Resource = "*", # sts:GetCallerIdentity does not support resource-level permissions
      },
      # --- S3 Read Access for Ansible Code ---
      {
        Effect   = "Allow",
        Action   = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation" # Often needed for `aws s3 sync`
        ],
        Resource = [
          "arn:aws:s3:::pet-bucket-new",
          "arn:aws:s3:::pet-bucket-new/ansible-code/*" # Only specific prefix
        ],
      },
      # --- S3 Read Access for Vault Policy Files (if using S3 for transfer) ---
      # Replace 'your-vault-policy-bucket-unique-name' with your actual bucket name
      {
        Effect   = "Allow",
        Action   = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::pet-bucket-new",
          "arn:aws:s3:::pet-bucket-new/policies/*" # Only specific prefix
        ],
      },
      # --- EC2 Read-Only Access (for dynamic inventory discovery, if needed) ---
      # This allows Ansible to list EC2 instances, but NOT modify them.
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeRegions",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ],
        Resource = "*"
      },
      # --- AWS Secrets Manager (if still fetching New Relic keys from there, otherwise remove) ---
      # If you're fully moving to Vault for New Relic, you can remove this block.
      # {
      #   Effect = "Allow",
      #   Action = "secretsmanager:GetSecretValue",
      #   Resource = [
      #     "arn:aws:secretsmanager:<YOUR_REGION>:<YOUR_AWS_ACCOUNT_ID>:secret:your-project/newrelic-api-key*",
      #     "arn:aws:secretsmanager:<YOUR_REGION>:<YOUR_AWS_ACCOUNT_ID>:secret:your-project/newrelic-account-id*"
      #   ],
      # },
    ]
  })
}

# Attach the custom policy to the Ansible role
resource "aws_iam_role_policy_attachment" "ansible_custom_policy_attach" {
  role       = aws_iam_role.ansible_role.name
  policy_arn = aws_iam_policy.ansible_custom_policy.arn
}

# Attach the AWS managed policy for SSM Agent functionality
# This is crucial for Session Manager access.
resource "aws_iam_role_policy_attachment" "ansible_ssm_managed_policy_attach" {
  role       = aws_iam_role.ansible_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM instance profile for ansible
resource "aws_iam_instance_profile" "ansible_instance_profile" { # Renamed to follow convention
  name = "ansible-profile" # This name is what you'll reference in the EC2 instance definition
  role = aws_iam_role.ansible_role.name
}

# resource "null_resource" "ansible-setup" {
#   provisioner "local-exec" {
#     command = <<EOT
#       aws s3 cp --recursive ${path.module}/script/ s3://pet-adoption-state-bucket-1/ansible-script/ 
#     EOT
#   } 
# }
