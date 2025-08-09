#!/bin/bash
set -euo pipefail # Exit immediately if a command exits with a non-zero status or an unset variable is used.

echo "Starting Ansible server bootstrap script..."

# --- 1. System Updates and Essential Tools ---
echo "Updating system and installing essential tools (wget, unzip, awscli, ansible-core, vault, jq)..."
sudo dnf update -y
sudo dnf install -y wget unzip jq 

# Install AWS CLI v2 
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -o /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

# Download the SSM Agent manually
sudo dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm

# Install Ansible Core
sudo dnf install -y ansible-core

# --- Install Vault CLI (with fallback if repo fails) ---
echo "Installing Vault..."
yum install -y unzip curl || { echo "Failed to install unzip/curl"; exit 1; }
# Try installing from repo first
yum install -y yum-utils >/dev/null 2>&1
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo >/dev/null 2>&1

if ! yum install -y vault; then
  echo "YUM install failed, falling back to manual Vault CLI install"
  cd /tmp || exit 1
  curl -s -O "https://releases.hashicorp.com/vault/${VAULT_VERSION}/${VAULT_ZIP}" || { echo "Failed to download Vault CLI"; exit 1; }
  unzip -o "${VAULT_ZIP}" >/dev/null || { echo "Failed to unzip Vault CLI"; exit 1; }
  install -m 0755 vault /usr/local/bin/ || { echo "Failed to install Vault binary"; exit 1; }
  rm -f "${VAULT_ZIP}" vault
else
  echo "Vault installed via YUM"
fi

# Verify Vault is available
if ! command -v vault >/dev/null; then
  echo "Vault CLI not found after install"
  exit 1
else
  echo "Vault CLI installed successfully: $(vault --version)"
fi


# --- 2. Securely Manage Ansible Code from S3 ---
echo "Creating Ansible code directory and syncing from S3..."
sudo mkdir -p /opt/ansible
sudo chown -R ec2-user:ec2-user /opt/ansible # Ensure ec2-user owns the directory

aws s3 sync s3://pet-bucket-new/ansible-code/latest/ /opt/ansible/


# --- 3. New Relic Installation (Fetch Key from VAULT ONLY) ---
echo "Configuring Vault access and installing New Relic agent..."

# Set VAULT_ADDR - crucial for the Vault CLI to know where your server is
# ADJUST THIS TO YOUR VAULT SERVER'S REACHABLE ADDRESS (e.g., private IP or internal DNS)
# If Vault is on the same instance, 'http://127.0.0.1:8200' is fine.
# If Vault is on a separate EC2 instance, use its private IP or internal DNS name.
export VAULT_ADDR='http://${vault_server_private_ip}:8200' # Example: 'http://10.0.1.10:8200'

# Login to Vault using the EC2 instance's IAM role
# The 'ansible-newrelic-reader' is the Vault role name you defined earlier.
echo "Logging into Vault..."
vault login -method=aws role=ansible-newrelic-reader

# Fetch New Relic secrets from Vault
echo "Fetching New Relic secrets from Vault..."
NEW_RELIC_SECRET_DATA=$(vault kv get -format=json kv/new-relic)
NEW_RELIC_API_KEY=$(echo "$${NEW_RELIC_SECRET_DATA}" | jq -r '.data.data.api_key')
NEW_RELIC_ACCOUNT_ID=$(echo "$${NEW_RELIC_SECRET_DATA}" | jq -r '.data.data.account_id')

# Install New Relic CLI and agent using secrets from Vault
echo "Installing New Relic agent with keys from Vault..."
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash \
  && sudo NEW_RELIC_API_KEY="$${NEW_RELIC_API_KEY}" \
             NEW_RELIC_ACCOUNT_ID="$${NEW_RELIC_ACCOUNT_ID}" \
             NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y

# --- 4. Final Touches ---
sudo hostnamectl set-hostname ansible-server
echo "Ansible server bootstrap script completed."
