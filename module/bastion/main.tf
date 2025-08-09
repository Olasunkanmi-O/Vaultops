# create security group
resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create IAM role for SSM
resource "aws_iam_role" "ssm-role" {
  name = "bastion-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach the SSM policy to the role
resource "aws_iam_role_policy_attachment" "ssm-policy" {
  role       = aws_iam_role.ssm-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# create IAM instance profile
resource "aws_iam_instance_profile" "ssm-profile" {
  name = "bastion-ssm-profile"
  role = aws_iam_role.ssm-role.name
}

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
resource "aws_launch_template" "bastion_launch_template" {
  name_prefix   = "bastion"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  iam_instance_profile {
    name = aws_iam_instance_profile.ssm-profile.name
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.bastion_sg.id]
    delete_on_termination       = true
  }

}

resource "aws_autoscaling_group" "bastion_atoscaling_group" {
  name                      = "bastion_atoscaling_group"
  max_size                  = 2
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 2
  force_delete              = true
  launch_template {
    id = aws_launch_template.bastion_launch_template.id
    version = "$Latest"
  }  
  vpc_zone_identifier       = var.subnets

  instance_maintenance_policy {
    min_healthy_percentage = 90
    max_healthy_percentage = 120
  }
  tag {
    key                 = "Name"
    value               = "app-bastion"
    propagate_at_launch = true
  }
}

# Create ASG policy for Bastion Host
resource "aws_autoscaling_policy" "bastion-asg-policy" {
  name                   = "app-bastion-asg-policy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.bastion_atoscaling_group.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}


