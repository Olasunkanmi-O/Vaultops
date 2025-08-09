variable "pri_sub1_id" {}
variable "pri_sub2_id" {}
variable "vpc_id" {}
variable "bastion_sg_id" {}
variable "stage_sg" {}
variable "prod_sg" {}
variable "db_admin_username" {
  description = "Initial master username for the RDS MySQL database."
  type        = string
  sensitive   = true # Mark as sensitive
}

variable "db_admin_password" {
  description = "Initial master password for the RDS MySQL database."
  type        = string
  sensitive   = true # Mark as sensitive
}

