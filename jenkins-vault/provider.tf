
provider "aws" {
  region  = var.region
  profile = "ola-devops"
}

terraform {
  backend "s3" {
    bucket = "pet-bucket-new"
    use_lockfile = true
    key    = "jenkins-vault/terraform.tfstate"
    region = "us-east-2"
    encrypt = true
    profile = "ola-devops"    
  }
}


