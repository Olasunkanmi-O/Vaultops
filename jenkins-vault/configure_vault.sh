#!/bin/bash
set -eo pipefail # Exit on error, exit on unset variables, exit on pipefail

echo "Starting Vault configuration script..."

# --- Configuration Variables ---
# IMPORTANT: Adjust these for your environment
VAULT_ADDR="http://127.0.0.1:8200" # Or your ELB URL if running remotely from another server
VAULT_ROOT_TOKEN_FILE="/opt/vault/root_token.txt" # Temporary file to store root token for script execution
VAULT_JENKINS_APPROLE_ROLE_ID_FILE="/opt/vault/jenkins_approle_role_id.txt" # File to store AppRole Role ID
VAULT_JENKINS_APPROLE_SECRET_ID_FILE="/opt/vault/jenkins_approle_secret_id.txt" # File to store AppRole Secret ID

echo "Setting VAULT_ADDR to: ${VAULT_ADDR}"
export VAULT_ADDR

# --- Wait for Vault to be unsealed ---
echo "Waiting for Vault to be unsealed..."
# Vault automatically unseals with KMS, but it takes a moment after startup.
# We'll poll its status until it's unsealed and initialized.
until vault status -format=json | jq -e '.sealed == false and .initialized == true'; do
  echo "Vault is still sealed or not initialized. Waiting..."
  sleep 5
done
echo "Vault is unsealed and initialized."

# --- Initialize Vault (if not already initialized) ---
# This part is critical. It will only run if Vault is not initialized.
# For auto-unseal, Vault is often initialized during its first boot.
# We'll check its status first.
INIT_STATUS=$(vault status -format=json || true) # Use || true to prevent script exiting if not initialized
if echo "${INIT_STATUS}" | jq -e '.initialized == false'; then
  echo "Vault is not initialized. Initializing Vault..."
  INIT_OUTPUT=$(vault operator init -format=json)
  ROOT_TOKEN=$(echo "${INIT_OUTPUT}" | jq -r '.root_token')
  # For recovery keys, if needed: RECOVERY_KEYS=$(echo "${INIT_OUTPUT}" | jq -r '.recovery_keys[]')

  if [ -z "${ROOT_TOKEN}" ]; then
    echo "ERROR: Failed to extract root token during initialization."
    exit 1
  fi

  echo "${ROOT_TOKEN}" > "${VAULT_ROOT_TOKEN_FILE}"
  chmod 600 "${VAULT_ROOT_TOKEN_FILE}" # Secure the token file
  echo "Vault initialized. Root token saved to ${VAULT_ROOT_TOKEN_FILE}"
  echo "IMPORTANT: Securely store your root token and recovery keys printed during init manually if you don't use this file!"
  echo "${INIT_OUTPUT}" # Print the full init output for manual saving of recovery keys
else
  echo "Vault is already initialized."
  # If already initialized, we assume the root token is either manually provided
  # or managed out-of-band for automation.
  # For this script to proceed, you might manually provide a root token if it's not the first run.
  # For simplicity here, we'll assume if it's initialized, we have a token or can login another way.
  # If you are restarting this script after a destroy and re-apply, you'd be re-initializing.
  # This part is mostly for robustness against re-runs on an already-running Vault.
  # For AppRole setup, we need *an* admin token.
  # In a real scenario, you'd manage this with Vault Agent or another secure method.
  echo "WARNING: Assuming an admin token is available for subsequent commands."
  # If you need to fetch a token securely here, you'd add that logic.
  # For now, if it's already initialized, the script continues assuming user has taken care of root token.
  # However, for a *fresh* deploy, the above init block *will* run and capture the token.
fi

# Log in using the root token (if available from init, otherwise manually export it before running this script)
if [ -f "${VAULT_ROOT_TOKEN_FILE}" ]; then
  ROOT_TOKEN=$(cat "${VAULT_ROOT_TOKEN_FILE}")
  export VAULT_TOKEN="${ROOT_TOKEN}"
  echo "Logging in with root token from file..."
  vault login -
  echo "Login successful."
else
  echo "WARNING: Root token file not found. Ensure VAULT_TOKEN environment variable is set manually for this script to proceed."
  # If VAULT_TOKEN is not set here, the script will likely fail at the next vault command.
  if [ -z "${VAULT_TOKEN}" ]; then
    echo "ERROR: VAULT_TOKEN is not set. Cannot proceed without authentication."
    exit 1
  fi
fi

# --- Enable KV Secrets Engine v2 at 'secret/' ---
echo "Attempting to enable KV secrets engine v2 at 'secret/'..."
if vault secrets enable -path=secret -version=2 kv; then
  echo "KV secrets engine (v2) enabled at 'secret/'."
else
  echo "KV secrets engine at 'secret/' might already be enabled or another error occurred. Checking..."
  # Check if it's already a KV v2 engine
  if vault read -format=json sys/mounts/secret/ | jq -e '.data.type == "kv" and .data.options.version == "2"'; then
    echo "KV secrets engine (v2) is already enabled at 'secret/'."
  else
    echo "ERROR: Could not enable KV secrets engine at 'secret/' or it's not KV v2. Please check manually."
    exit 1
  fi
fi

# --- Enable AppRole Authentication Method ---
echo "Enabling AppRole authentication method..."
if vault auth enable approle; then
  echo "AppRole authentication method enabled."
else
  echo "AppRole authentication method might already be enabled. Checking..."
  if vault auth list -format=json | jq -e '."approle/" != null'; then
    echo "AppRole authentication method is already enabled."
  else
    echo "ERROR: Could not enable AppRole authentication method. Please check manually."
    exit 1
  fi
fi

# --- Create Vault Policy for Jenkins (`jenkins-policy`) ---
echo "Creating/updating Vault policy 'jenkins-policy'..."
cat << EOF > /tmp/jenkins-policy.hcl
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
vault policy write jenkins-policy /tmp/jenkins-policy.hcl
echo "Vault policy 'jenkins-policy' created/updated."

# --- Create AppRole for Jenkins (`jenkins-approle`) ---
echo "Creating/updating AppRole 'jenkins-approle'..."
vault write auth/approle/role/jenkins-approle token_ttl=1h token_max_ttl=4h policies="jenkins-policy"
echo "AppRole 'jenkins-approle' created/updated."

# --- Get AppRole Role ID ---
echo "Retrieving AppRole Role ID..."
ROLE_ID=$(vault read -field=role_id auth/approle/role/jenkins-approle/role-id)
if [ -z "${ROLE_ID}" ]; then
  echo "ERROR: Failed to retrieve AppRole Role ID."
  exit 1
fi
echo "${ROLE_ID}" > "${VAULT_JENKINS_APPROLE_ROLE_ID_FILE}"
echo "AppRole Role ID saved to ${VAULT_JENKINS_APPROLE_ROLE_ID_FILE}: ${ROLE_ID}"

# --- Generate AppRole Secret ID ---
echo "Generating AppRole Secret ID..."
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/jenkins-approle/secret-id)
if [ -z "${SECRET_ID}" ]; then
  echo "ERROR: Failed to generate AppRole Secret ID."
  exit 1
fi
echo "${SECRET_ID}" > "${VAULT_JENKINS_APPROLE_SECRET_ID_FILE}"
echo "AppRole Secret ID saved to ${VAULT_JENKINS_APPROLE_SECRET_ID_FILE}: ${SECRET_ID}"

# --- Store Test Secret ---
echo "Storing test secret 'secret/jenkins/my-test-secret'..."
vault kv put secret/jenkins/my-test-secret message="HelloFromVault!"
echo "Test secret stored."

echo "Vault configuration script finished successfully."
echo ""
echo "--- IMPORTANT: MANUAL STEPS ---"
echo "1. Securely copy the Role ID from ${VAULT_JENKINS_APPROLE_ROLE_ID_FILE} and Secret ID from ${VAULT_JENKINS_APPROLE_SECRET_ID_FILE}."
echo "2. Use these in Jenkins for the Vault plugin configuration."
echo "3. Remember to delete ${VAULT_ROOT_TOKEN_FILE} if it was created for temporary use."
echo "4. The initial root token and recovery keys were printed during 'vault operator init'. SAVE THEM SECURELY OFF-HOST."