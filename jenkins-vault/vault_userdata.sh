#!/bin/bash
set -e

# Logging
#exec > >(tee /var/log/vault-setup.log|logger -t vault-setup -s 2>/dev/console) 2>&1

export DEBIAN_FRONTEND=noninteractive

echo "1. Installing prerequisites..."
apt update -yq && apt install -yq gnupg curl unzip lsb-release software-properties-common

echo "2. Adding HashiCorp GPG key..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "3. Adding HashiCorp repo..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list

apt update -yq
apt install -yq vault

echo "4. Creating Vault config & data directories..."
mkdir -p /etc/vault.d /opt/vault/data
chown -R vault:vault /etc/vault.d /opt/vault/data
chmod 700 /etc/vault.d

export kms_key_id=$(terraform output -raw vault_kms_key_arn)
export vault_region=$(terraform output -raw vault_region) # Assuming you have this too
export vault_storage=$(terraform output -raw vault_s3_bucket_name) # And this

echo "5. Writing Vault config..."
cat <<EOF_VAULT > /etc/vault.d/vault.hcl
storage "s3" {
  bucket     = "${vault_storage}"
  region     = "${vault_region}"
  prefix     = "vault-storage/"
}

seal "awskms" {
  kms_key_id = "${kms_key_id}"
  region     = "${vault_region}"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

ui = true
disable_mlock = true
EOF_VAULT

echo "6. Setting up systemd service..."
systemctl enable vault
systemctl start vault
systemctl status vault --no-pager

echo "7. Finished Vault bootstrap."
