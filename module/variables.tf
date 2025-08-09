

variable "region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to deploy resources"
}

variable "db_admin_username" {
  description = "Initial master username for the RDS MySQL database."
  type        = string
  sensitive   = true
}

variable "db_admin_password" {
  description = "Initial master password for the RDS MySQL database."
  type        = string
  sensitive   = true
}

variable "domain_name" {
  type        = string
  default     = "alasoasiko.co.uk"
  description = "Domain name used in Route53 and ACM"
}

variable "vault_server_private_ip" {
  description = "The private IP address of the Vault server. This should be a reachable IP from the Ansible server."
  type        = string
}

variable "sonarqube_role_id" {
  description = "role id for sonarqube to access vault"
  type = string
}

variable "sonarqube_secret_id" {
  description = "secret id for sonarqube to access vault"
  type = string
}