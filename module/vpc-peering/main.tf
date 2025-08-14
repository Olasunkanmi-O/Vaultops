# Fetch Vault outputs from the Vault backend
data "terraform_remote_state" "vault" {
  backend = "s3"
  config = {
    bucket  = "pet-bucket-new"
    key     = "jenkins-vault/terraform.tfstate"
    region  = "us-east-2"
    encrypt = true
    #profile = "ola-devops"
  }
}


# Fetch VPC, SG, and private route table IDs from Vault
data "aws_vpc" "vault_vpc" {
  id = data.terraform_remote_state.vault.outputs.vault_vpc_id
}

data "aws_security_group" "vault_sg" {
  id = data.terraform_remote_state.vault.outputs.vault_sg_id
}

data "aws_route_table" "vault_rt_lookup" {
  filter {
    name   = "route-table-id"
    values = [data.terraform_remote_state.vault.outputs.vault_private_route_table_id]
  }
}

# -----------------------------------------------------------------------------
# VPC PEERING CONNECTION
# -----------------------------------------------------------------------------

# Create the VPC peering connection from the Vault VPC to the App VPC.
# The `requester` and `accepter` roles are determined by the provider.
resource "aws_vpc_peering_connection" "peering" {
  vpc_id        = data.aws_vpc.vault_vpc.id  //vpc where vault resides
  peer_vpc_id   = var.app_vpc_id    // vpc where the other resources (database, sonarqube,) reside
  auto_accept   = false  # We will explicitly accept it below

  tags = {
    Name = "vault-to-app-peering"
  }
}

# Accept the peering connection from the App VPC side.
# This resource requires the `peer_vpc_id` to be the App VPC ID
# and the `vpc_id` to be the Vault VPC ID, as it is from the accepter's perspective. (this method is useful for different aws accounts)
resource "aws_vpc_peering_connection_accepter" "accepter" {
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
  auto_accept               = true

  tags = {
    Name = "app-to-vault-peering-accepter"
  }
}

# Add a route to the Vault private route table for the App VPC CIDR block.
# This directs traffic for the App VPC through the peering connection.
resource "aws_route" "vault_peering_route" {
  route_table_id            = data.aws_route_table.vault_rt_lookup.id  //the id of the private route table for vault 
  destination_cidr_block    = var.cidr_block          // the cidr block of the vpc of the other resources for easy communication
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id    //the peering connection id to identify both resources
}

# Add a route to the App private route table for the Vault VPC CIDR block.
# This directs traffic for the Vault VPC through the peering connection.
resource "aws_route" "app_peering_route" {
  route_table_id            = var.app_private_rt_lookup  
  destination_cidr_block    = data.aws_vpc.vault_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}

# Add a route to the App Public Route Table for the Vault VPC CIDR block.
resource "aws_route" "app_public_peering_route" {
  route_table_id            = var.app_public_rt_lookup
  destination_cidr_block    = data.aws_vpc.vault_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}


# # Fetch App outputs from the App backend
# data "terraform_remote_state" "app" {
#   backend = "s3"
#   config = {
#     bucket  = "pet-bucket-new"
#     key     = "infrastructure/terraform.tfstate"
#     region  = "us-east-2"
#     encrypt = true
#     profile = "ola-devops"
#   }
# }

# # Fetch VPC, RDS SG, and private route table IDs from APP
# data "aws_vpc" "app_vpc" {
#   id = data.terraform_remote_state.app.outputs.app_vpc_id
# }

# data "aws_security_group" "app_rds_sg" {
#   id = data.terraform_remote_state.app.outputs.mysql_security_group_id
# }

# data "aws_route_table" "app_private_rt_lookup" {
#   filter {
#     name   = "route-table-id"
#     values = [data.terraform_remote_state.app.outputs.app_private_route_table_id]
#   }
# }

# # Fetch the App VPC Public Route Table ID
# # This assumes the public route table has a unique name tag.
# data "aws_route_table" "app_public_rt_lookup" {
#   filter {
#     name   = "tag:Name"
#     values = ["your-app-public-route-table-name"]
#   }
# }
