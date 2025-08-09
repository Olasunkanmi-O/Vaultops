variable "vpc_id" {}
variable "bastion_sg_id" {}
variable "pri_sub2_id" {}
variable "vault_server_private_ip" {
  description = "The private IP address of the Vault server. This should be a reachable IP from the Ansible server."
  type        = string
}