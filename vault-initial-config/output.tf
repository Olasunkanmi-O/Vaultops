output "stage_role_id" {
  value       = vault_approle_auth_backend_role.app_stage.role_id
  sensitive   = true
}

output "prod_role_id" {
  value       = vault_approle_auth_backend_role.app_prod.role_id
  sensitive   = true
}

output "ansible_newrelic_secret_id" {
  value       = vault_approle_auth_backend_role_secret_id.ansible_newrelic_secret_id.id
  description = "Use this in Ansible for Vault AppRole auth"
  sensitive   = true
}

output "ansible_newrelic_role_id" {
  value       = vault_approle_auth_backend_role.ansible_newrelic.role_id
  description = "Use this in Ansible for Vault AppRole auth"
  sensitive   = true
}

output "sonarqube_role_id" {
  description = "The role_id for the SonarQube AppRole"
  value       = vault_approle_auth_backend_role.sonarqube_read_role.role_id
}

output "sonarqube_secret_id" {
  description = "The secret_id for the SonarQube AppRole"
  value       = vault_approle_auth_backend_role_secret_id.sonarqube_secret_id.secret_id
  sensitive = true
}