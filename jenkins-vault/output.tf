output "acm_certificate_id" {
  value = aws_acm_certificate.cert.arn
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.cert.id
}

output "vault_kms_key_arn" {
  value = aws_kms_key.vault_auto_unseal_key.arn
  description = "ARN of the KMS key used for Vault auto-unseal."
}

output "vault_s3_bucket_name" {
  description = "The name of the S3 bucket used for Vault storage."
  value       = data.aws_s3_bucket.shared_bucket_data.bucket
}

output "vault_region" {
  description = "The AWS region where Vault is deployed."
  value       = var.vault_region
}

output "vault_server_private_ip" {
  value = aws_instance.vault-server.private_ip
}

output "vault_elb_dns_name" {
  description = "The DNS name of the Vault ELB."
  value       = aws_elb.elb_vault.dns_name
}

output "vault_url" {
  description = "The full HTTPS URL for the Vault ELB."
  value       = "https://${aws_route53_record.vault-record.name}"
}


# Output the VPC ID created by this module
output "vault_vpc_id" {
  description = "The ID of the VPC created by the jenkins-vault module"
  value       = aws_vpc.jv-vpc.id
}

#Output the private subnet IDs created by this module
output "pri_sub1_id" {
  description = "ID of the first private subnet created by jenkins-vault module"
  value       = aws_subnet.pri_sub1.id
}

output "vault_sg_id" {
  value       = aws_security_group.vault_sg.id
  description = "Security Group ID for Vault instance"
}

output "vault_private_route_table_id" {
  value       = aws_route_table.pri_rt.id
  description = "Private Route Table ID for Vault private subnet"
}







