variable "vpc_id" {}
variable "bastion_sg" {}
variable "ansible_sg" {}
variable "pri_sub1" {}
variable "pri_sub2" {}
variable "pub_sub1" {}
variable "pub_sub2" {}
variable "acm_cert_arn" {}
variable "domain_name" {}
variable "route_53_zone_id" {}
variable "environment" {
  default = "stage"
}