Project Documentation: Jenkins-Vault on AWS
1. Project Overview
This project establishes a secure, scalable Continuous Integration/Continuous Delivery (CI/CD) environment using Jenkins and a centralized secrets management solution with HashiCorp Vault, both deployed within a dedicated Amazon Web Services (AWS) Virtual Private Cloud (VPC).

The setup ensures:

Secure Networking: Instances are primarily in private subnets, accessing the internet via a NAT Gateway.

Automated Provisioning: Infrastructure is defined and deployed using Terraform.

Secrets Management: Vault securely stores and manages sensitive data.

CI/CD Integration: Jenkins retrieves secrets from Vault for its build and deployment processes using AppRole authentication.

2. AWS Infrastructure Provisioning (Terraform)
All AWS resources are provisioned using Terraform, ensuring infrastructure as code, reproducibility, and version control.

2.1. VPC and Networking
A dedicated VPC is created with public and private subnets across a single Availability Zone (us-east-1a). This setup provides controlled internet access for private resources.

VPC CIDR: 12.0.0.0/16

Public Subnet CIDR: 12.0.1.0/24 (for NAT Gateway, ELBs)

Private Subnet CIDR: 12.0.2.0/24 (for Jenkins and Vault EC2 instances)

Internet Gateway (IGW): Provides internet connectivity for the VPC.

NAT Gateway (NAT GW): Deployed in the public subnet to allow instances in private subnets outbound internet access.

Route Tables: Configured to direct traffic appropriately (public subnets to IGW, private subnets to NAT GW).

DNS: DNS hostnames and support are enabled for the VPC.

Terraform Configuration (vpc.tf or similar):

Terraform

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "jenkins-vault-vpc"
  cidr = "12.0.0.0/16"

  azs             = ["us-east-1a"]
  public_subnets  = ["12.0.1.0/24"]
  private_subnets = ["12.0.2.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = true
  enable_dns_hostnames    = true
  enable_dns_support      = true

  tags = {
    Terraform = "true"
    Project   = "JenkinsVault"
  }
}
2.2. Jenkins Server Deployment
The Jenkins server is deployed as an EC2 instance within the private subnet, fronted by a Classic Load Balancer (ELB) for secure external access.

EC2 Instance:

AMI: Latest Ubuntu Jammy 22.04 LTS.

Instance Type: t3.medium.

Subnet: module.vpc.private_subnets[0] (private subnet in us-east-1a).

User Data: A shell script (jenkins_userdata.sh) to install Jenkins, Java, Docker, Docker Compose, and configure necessary services.

Root Volume: 20GB gp3 encrypted.

Security Group (jenkins_sg):

Ingress: Allows TCP port 8080 only from the Jenkins ELB's security group.

Egress: Allows all outbound traffic (0.0.0.0/0) for updates and internet access.

IAM Role & Instance Profile (jenkins_ssm_role):

Allows the Jenkins EC2 instance to assume an EC2 service role.

Attached policies: AmazonSSMManagedInstanceCore (for Session Manager access) and AdministratorAccess (for broad permissions during initial setup/testing, should be scoped down for production).

Classic Load Balancer (elb_jenkins):

Subnets: module.vpc.public_subnets (public subnet for external accessibility).

Listener:

Frontend: HTTPS:443

Backend: HTTP:8080 (to Jenkins instance)

SSL Certificate: Managed by AWS Certificate Manager (ACM).

Health Check: TCP:8080.

ACM Certificate: For *.${var.domain_name} and ${var.domain_name}. Validated via Route 53 DNS records.

Route 53 DNS Record: An A record for jenkins.${var.domain_name} pointing to the Jenkins ELB.

Key Terraform Snippets (for jenkins.tf or similar):

Terraform

# Jenkins EC2 Instance
resource "aws_instance" "jenkins-server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = module.vpc.private_subnets[0]
  availability_zone           = module.vpc.azs[0]
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins_instance_profile.name
  user_data                   = file("${path.module}/jenkins_userdata.sh")
  root_block_device { volume_size = 20; volume_type = "gp3"; encrypted = true }
  metadata_options { http_tokens = "required" }
  tags = { Name = "jenkins-server" }
}

# jenkins_userdata.sh (excerpt - detailed script contents separate)
# Example:
#!/bin/bash
sudo apt update -y
sudo apt install -y openjdk-17-jre
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update -y
sudo apt install -y jenkins
# ... install docker, docker-compose, configure permissions
sudo usermod -aG docker jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins
2.3. Vault Server Deployment
The Vault server is deployed as an EC2 instance in the private subnet, using AWS KMS for auto-unseal and S3 for storage. It's fronted by a Classic Load Balancer (ELB).

EC2 Instance:

AMI: Latest Ubuntu Jammy 22.04 LTS.

Instance Type: t3.medium.

Subnet: module.vpc.private_subnets[0] (private subnet in us-east-1a).

User Data: A shell script (vault_userdata.sh) to install Vault, configure its HCL, set up systemd service, and perform auto-unseal.

Root Volume: 20GB gp3 encrypted.

Security Group (vault_server_sg):

Ingress: Allows TCP port 8200 from the Jenkins instance's security group (for integration) and from the Vault ELB's security group.

Egress: Allows all outbound traffic (0.0.0.0/0).

IAM Role & Instance Profile (vault_server_role):

Allows the Vault EC2 instance to assume an EC2 service role.

Attached policies: AmazonSSMManagedInstanceCore, permissions for KMS (kms:Encrypt, kms:Decrypt, kms:DescribeKey) and S3 (s3:PutObject, s3:GetObject, s3:DeleteObject, s3:ListBucket) for auto-unseal and storage backend.

KMS Key: Used for Vault's auto-unseal functionality (alias/vault-auto-unseal-key).

S3 Bucket: Used as Vault's storage backend (${var.vault_storage}).

Classic Load Balancer (elb_vault):

Subnets: module.vpc.public_subnets (public subnet).

Listener:

Frontend: HTTP:8200

Backend: HTTP:8200 (to Vault instance)

Note: TLS is disabled on the Vault instance for initial setup (tls_disable = "true"). For production, TLS should be enabled and configured on the ELB and ideally on the Vault server itself.

Health Check: TCP:8200.

Route 53 DNS Record: An A record for vault.${var.domain_name} pointing to the Vault ELB.

Key Terraform Snippets (for vault.tf or similar):

Terraform

# Vault EC2 Instance
resource "aws_instance" "vault_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = module.vpc.private_subnets[0]
  availability_zone           = module.vpc.azs[0]
  vpc_security_group_ids      = [aws_security_group.vault_server_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_server_profile.name
  associate_public_ip_address = false # Private instance
  user_data                   = file("${path.module}/vault_userdata.sh")
  tags = { Name = "vault-server" }
}

# vault_userdata.sh (excerpt - detailed script contents separate)
# Example:
#!/bin/bash
sudo apt update -y
sudo apt install -y gnupg software-properties-common curl
# ... Install Vault binary ...
sudo mkdir -p /etc/vault.d
cat << EOF | sudo tee /etc/vault.d/vault.hcl
storage "s3" {
  bucket = "${var.vault_storage}"
  region = "${var.region}"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true" # !! IMPORTANT: CHANGE FOR PRODUCTION !!
}

seal "awskms" {
  kms_key_id     = "${aws_kms_alias.vault_unseal_key_alias.target_key_arn}"
  kms_encryption_context = {
    "VaultCluster" = "jenkins-vault"
  }
}

ui = true
EOF
# ... systemd service setup, start/enable Vault
3. Vault Server Initial Setup & Configuration
After the Vault EC2 instance is running, manual steps are required for initial setup and subsequent configuration for Jenkins integration. All commands are run from the Vault EC2 instance via AWS SSM Session Manager.

Prerequisites:

Connect to Vault EC2 instance: aws ssm start-session --target <Vault-EC2-Instance-ID>

Set Vault Address (critical as TLS is disabled): export VAULT_ADDR='http://127.0.0.1:8200'

3.1. Initialization & Unseal
Upon first startup, Vault is sealed. It automatically unseals using AWS KMS due to the seal "awskms" configuration.

Manual Initialization (first time only):

Bash

vault operator init
CRITICAL: This command outputs the Root Token and Recovery Keys. Save these securely in an offline location. These are essential for initial access and disaster recovery.

3.2. Enable KV Secrets Engine (Version 2)
By default, the secret/ path for Key-Value secrets is not enabled. We explicitly enable KV Version 2, which vault kv put/get commands operate on.

Bash

vault secrets enable -path=secret -version=2 kv
Expected Output: Success! Enabled the kv secrets engine at: secret/

3.3. AppRole Authentication Setup for Jenkins
AppRole is used for machine-to-machine authentication between Jenkins and Vault.

Log in to Vault (as root or a user with sudo policy on sys/auth and sys/policy):

Bash

vault login <your_initial_root_token_here>
Verify login: vault token lookup (should show policies ["root"])

Enable AppRole Authentication Method:

Bash

vault auth enable approle
Expected: Success! Enabled approle auth method at: approle/

Create Vault Policy for Jenkins (jenkins-policy.hcl):
This policy grants Jenkins read/list access to secrets under secret/data/jenkins/.

Bash

cat << EOF > jenkins-policy.hcl
path "secret/data/jenkins/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/jenkins/*" {
  capabilities = ["read", "list"]
}
path "auth/approle/login" {
  capabilities = ["create", "read"]
}
EOF
Bash

vault policy write jenkins-policy jenkins-policy.hcl
Expected: Success! Uploaded policy: jenkins-policy

Create AppRole for Jenkins (jenkins-approle):

Bash

vault write auth/approle/role/jenkins-approle token_ttl=1h token_max_ttl=4h policies="jenkins-policy"
Get AppRole Role ID:

Bash

vault read auth/approle/role/jenkins-approle/role-id
SAVE THIS role_id SECURELY!

Generate AppRole Secret ID:

Bash

vault write -f auth/approle/role/jenkins-approle/secret-id
SAVE THIS secret_id SECURELY! Treat it like a password.

3.4. Storing a Test Secret
A simple test secret is stored in Vault at secret/jenkins/my-test-secret for Jenkins to retrieve.

Bash

vault kv put secret/jenkins/my-test-secret message="HelloFromVault!"
Expected: Success! Data written to: secret/jenkins/my-test-secret

Verify (get only the data): vault kv get -field=message secret/jenkins/my-test-secret (should output HelloFromVault!)

4. Jenkins Server Configuration
After the Jenkins EC2 instance is running and accessible via ELB, additional steps are required within the Jenkins UI to integrate with Vault.

4.1. Initial Jenkins Setup (First Access)
Access Jenkins UI: Navigate to https://jenkins.${var.domain_name}.

Unlock Jenkins: Retrieve initial admin password from EC2 instance:

Bash

aws ssm start-session --target <Jenkins-EC2-Instance-ID>
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
Enter password in UI.

Install Plugins: Choose "Install suggested plugins".

Create Admin User: Create your first admin user credentials.

4.2. Install HashiCorp Vault Plugin
Log in to Jenkins.

Go to Manage Jenkins > Plugins.

Click "Available plugins" tab.

Search for HashiCorp Vault, check the box, and click "Install without restart".

Restart Jenkins if prompted.

4.3. Configure Global Vault Plugin Settings
This links Jenkins to your Vault server and defines how it authenticates.

Log in to Jenkins.

Go to Manage Jenkins > Credentials > System > Global credentials (unrestricted).

Click Add Credentials.

Kind: Secret text

Secret: Your AppRole secret_id (from Vault).

ID: vault-jenkins-approle-secret-id (arbitrary, used to reference this credential).

Click Create.

Go to Manage Jenkins > System.

Scroll to "HashiCorp Vault Plugin" section.

Click Add Vault Configuration.

Vault URL: https://vault.${var.domain_name} (your Vault ELB URL).

Vault Credential:

Click Add button.

Kind: Vault App Role Credential

Role ID: Your AppRole role_id (from Vault).

Secret ID: Select vault-jenkins-approle-secret-id from the dropdown.

Path: approle

ID: jenkins-vault-approle (arbitrary, identifies this specific AppRole configuration).

Click Add.

Select jenkins-vault-approle from the main Vault Credential dropdown.

Skip SSL Verification: Check this box only for non-production environments if your Vault ELB does not have a trusted SSL certificate (as per current tls_disable=true).

Click Test Connection (should show "Connected").

Click Save at the bottom.

5. Jenkins Pipeline for Secret Retrieval
A Jenkins Pipeline job demonstrates how to fetch a secret from Vault using the withVault step provided by the plugin.

Steps:

Log in to Jenkins.

Click New Item.

Item name: Vault-Secret-Test.

Type: Pipeline.

Click OK.

In the "Pipeline" section, set "Definition" to Pipeline script.

Paste the following Groovy script:

Groovy

pipeline {
    agent any

    stages {
        stage('Retrieve Secret from Vault') {
            steps {
                script {
                    withVault(
                        configuration: [
                            vaultUrl: 'https://vault.alasoasiko.co.uk', // Your Vault ELB URL
                            vaultCredentialId: 'jenkins-vault-approle', // The ID of the Vault AppRole Credential
                            engineVersion: 2 // Specify KV Engine version 2
                        ],
                        vaultSecrets: [
                            [
                                path: 'secret/jenkins/my-test-secret', // Path to secret in Vault
                                secretValues: [
                                    [
                                        vaultKey: 'message', // Key within the secret
                                        envVar: 'MY_VAULT_MESSAGE' // Env var to set in Jenkins
                                    ]
                                ]
                            ]
                        ]
                    ) {
                        sh 'echo "The secret message from Vault is: ${MY_VAULT_MESSAGE}"'
                    }
                }
            }
        }
    }
}
Update vaultUrl with your actual Vault ELB URL.

Ensure vaultCredentialId matches the ID you set (jenkins-vault-approle).

Click Save.

Run the job: Click "Build Now" and check the Console Output.

Expected Result: The console output should display: The secret message from Vault is: HelloFromVault!