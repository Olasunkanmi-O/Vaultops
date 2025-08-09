output "ansible_sg" {
  value = aws_security_group.ansible-sg.id
}

output "ansible_instance_profile" {
  value = aws_iam_instance_profile.ansible_instance_profile.arn
}