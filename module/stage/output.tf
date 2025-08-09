output "stage_sg" {
  value = aws_security_group.stage-sg.id
}

output "stage_instance_profile" {
  value = aws_iam_instance_profile.stage_instance_profile.arn
}
