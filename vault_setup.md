# Vault Server Initial Setup Plan
This guide outlines the manual steps to configure your Vault server after it has successfully booted up, and before launching any client servers (like Ansible or application servers).

### Assumptions:

- Your Vault EC2 instance has been launched, and the Vault service is running and accessible.
- The Vault server is configured for KMS auto-unseal via its IAM Instance Profile, meaning it should automatically unseal upon startup/reboot.
- You are performing these steps by connecting directly to the Vault server instance via AWS SSM Session Manager.

### Steps to Configure Vault
1. Access the Vault Server and Set Environment Variable
First, establish a session with your Vault EC2 instance and set the VAULT_ADDR environment variable.
    1. Connect to your Vault server:
        - Go to the AWS Console -> EC2 -> Instances.
        - Select your Vault server instance.
        - Click "Actions" -> "Connect" -> "Session Manager" -> "Connect".
    2. On the Vault server's terminal, set `VAULT_ADDR`:

    ```Bash
    export VAULT_ADDR='http://127.0.0.1:8200'
    ```
    Note: If your Vault server is configured to listen on a specific internal IP, or if you're accessing it from a different machine within the VPC, VAULT_ADDR should be that specific internal IP or DNS name. For commands run directly on the Vault server, `127.0.0.1` is typically correct if Vault binds to localhost.
2. Initialize Vault (First Time Setup)
Initialize the Vault server. This is a one-time operation that generates the initial root token and unseal keys.

```Bash
vault operator init
```
    ⚠️ CRITICAL: Immediately securely save the Recovery Key values (all 5) and the Initial Root Token that are outputted. Store them in a secure, offline location (e.g., a secrets vault, secure password manager, or split among trusted individuals). The Initial Root Token is required for your first login to configure Vault. The Recovery Keys are vital for disaster recovery in case auto-unseal fails or is disabled.

3. Log In to Vault with the Root Token
You must log in as a privileged user to perform any configuration.

```Bash
vault login <YOUR_INITIAL_ROOT_TOKEN>
```
    Replace <YOUR_INITIAL_ROOT_TOKEN> with the token you saved from the vault operator init output.

