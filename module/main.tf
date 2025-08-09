# calling hosted zone
data "aws_route53_zone" "zone" {
  name         = var.domain_name
  private_zone = false
}

#calling acm certificate
data "aws_acm_certificate" "cert" {
  domain      = var.domain_name
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}


module "vpc" {
  source = "./vpc"
  az1    = "us-east-2a"
  az2    = "us-east-2b"
}

module "ansible" {
  source                  = "./ansible"
  vpc_id                  = module.vpc.vpc_id
  pri_sub2_id             = module.vpc.pri_sub2_id
  bastion_sg_id           = module.bastion.bastion_sg_id
  vault_server_private_ip = var.vault_server_private_ip
}

module "bastion" {
  source  = "./bastion"
  vpc_id  = module.vpc.vpc_id
  subnets = [module.vpc.pub_sub1_id, module.vpc.pri_sub2_id]
}

module "nexus" {
  source         = "./nexus"
  vpc_id         = module.vpc.vpc_id
  hosted_zone_id = data.aws_route53_zone.zone.id
  domain_name    = var.domain_name
  pub_sub1_id    = module.vpc.pub_sub1_id
  pub_sub2_id    = module.vpc.pub_sub2_id
  certificate    = data.aws_acm_certificate.cert.arn
}

module "sonarqube" {
  source         = "./sonarqube"
  vpc_id         = module.vpc.vpc_id
  hosted_zone_id = data.aws_route53_zone.zone.id
  domain_name    = var.domain_name
  pub_sub1_id    = module.vpc.pub_sub1_id
  pub_sub2_id    = module.vpc.pub_sub2_id
  certificate    = data.aws_acm_certificate.cert.arn
  depends_on = [ module.vpc-peering ]
  sonarqube_role_id = var.sonarqube_role_id
  sonarqube_secret_id = var.sonarqube_secret_id
}

module "stage" {
  source           = "./stage"
  vpc_id           = module.vpc.vpc_id
  bastion_sg       = module.bastion.bastion_sg_id
  ansible_sg       = module.ansible.ansible_sg
  pri_sub1         = module.vpc.pri_sub1_id
  pri_sub2         = module.vpc.pri_sub2_id
  pub_sub1         = module.vpc.pub_sub1_id
  pub_sub2         = module.vpc.pub_sub2_id
  acm_cert_arn     = data.aws_acm_certificate.cert.arn
  domain_name      = var.domain_name
  route_53_zone_id = data.aws_route53_zone.zone.id
}

module "prod" {
  source           = "./prod"
  vpc_id           = module.vpc.vpc_id
  bastion_sg       = module.bastion.bastion_sg_id
  ansible_sg       = module.ansible.ansible_sg
  pri_sub1         = module.vpc.pri_sub1_id
  pri_sub2         = module.vpc.pri_sub2_id
  pub_sub1         = module.vpc.pub_sub1_id
  pub_sub2         = module.vpc.pub_sub2_id
  acm_cert_arn     = data.aws_acm_certificate.cert.arn
  domain_name      = var.domain_name
  route_53_zone_id = data.aws_route53_zone.zone.id
}

module "database" {
  source            = "./database"
  pri_sub1_id       = module.vpc.pri_sub1_id
  pri_sub2_id       = module.vpc.pri_sub2_id
  vpc_id            = module.vpc.vpc_id
  bastion_sg_id     = module.bastion.bastion_sg_id
  stage_sg          = module.stage.stage_sg
  prod_sg           = module.prod.prod_sg
  db_admin_username = var.db_admin_username
  db_admin_password = var.db_admin_password
  
}

module "vpc-peering" {
  source                = "./vpc-peering"
  app_vpc_id            = module.vpc.vpc_id
  cidr_block            = module.vpc.cidr_block
  app_public_rt_lookup  = module.vpc.app_public_route_table_id
  app_private_rt_lookup = module.vpc.app_private_route_table_id
}