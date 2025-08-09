variable "vpc_id" {}
variable "pub_sub1_id" {}
variable "pub_sub2_id" {}
variable "certificate" {}
variable "hosted_zone_id" {}
variable "domain_name" {}
variable "sonarqube_role_id" {
  description = "The AppRole role_id for SonarQube to authenticate with Vault."
  type        = string
}

variable "sonarqube_secret_id" {
  description = "The AppRole secret_id for SonarQube to authenticate with Vault."
  type        = string
  sensitive   = true
}

variable "sonarqube_version" {
  description = "version of sonarqube"
  default = "25.5.0.107428"
}

variable "sonar_zip" {
  default = "sonarqube-25.5.0.107428.zip"
}