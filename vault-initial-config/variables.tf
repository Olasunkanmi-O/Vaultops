variable "newrelic_api_key" {
  type        = string
  description = "New Relic API Key"
  sensitive   = true
}

variable "newrelic_user_id" {
  type        = string
  description = "New Relic User ID"
  sensitive   = true
}

variable "vault_address" {
  description = "The full URL of the Vault server (e.g., https://vault.yourdomain.com)."
  type        = string
}

variable "vault_token" {
  description = "A Vault token with sufficient permissions (e.g., root token or initial admin token) to configure Vault."
  type        = string
  sensitive   = true # Mark as sensitive so Terraform redacts it from output
}

variable "sonarqube_db_username" {
  description = "initial username for sonarqube db"
  type = string
}

variable "sonarqube_db_password" {
  description = "initial password for sonarqube db"
  type = string
}

variable "domain_name" {
  description = "Your primary domain name for policy paths or other references."
  type        = string
}

variable "db_static_username" {
  type        = string
  description = "The static username for the petclinic database"
  sensitive   = true
}

variable "db_static_password" {
  type        = string
  description = "The static password for the petclinic database"
  sensitive   = true
}