output "prod_sg" {
  value = aws_security_group.prod-sg.id
}

output "prod_instance_profile" {
  value = aws_iam_instance_profile.prod_instance_profile.arn
}