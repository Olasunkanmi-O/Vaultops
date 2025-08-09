variable "region" {
  default = "us-east-2"
}

variable "vault_region" {
  default = "us-east-2"
}

variable "az1" {
  default = "us-east-2a"
}

variable "domain_name"{
  default = "alasoasiko.co.uk"
}

variable "vault_kms_key_alias" {
  description = "Alias for the KMS key used for Vault auto-unseal."
  type        = string
  default     = "alias/vault-auto-unseal-key" # Common practice to use an alias
}

variable "vault_storage" {
  description = "name of the s3 bucket"
  type = string
  default = "pet-bucket-new"  
}



