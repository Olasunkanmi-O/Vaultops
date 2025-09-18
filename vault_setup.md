:

# Project Bridge Phase: Vault Server Initial Setup

This phase is a **manual, critical step** performed immediately after the **Phase 1 setup script** successfully deploys the Vault EC2 instance. It involves the initial one-time generation of security artifacts (Root Token, Recovery Keys) necessary to begin automating Vault configuration via Jenkins (Phase 2).

> **Goal:** Initialize the Vault server, secure the Root Token, and prepare the environment for subsequent automation.

-----

## Assumptions & Access

The following prerequisites must be met before starting the setup:

  * **Phase 1 Success:** The Terraform code in `jenkins-vault` has successfully deployed the Vault EC2 instance and the Vault service is running.
  * **Auto-Unseal:** The Vault server is configured for **KMS Auto-Unseal** via its IAM Instance Profile, meaning the server should be in an **unsealed** state upon startup.
  * **Access Method:** You will connect directly to the Vault server instance, preferably using **AWS SSM Session Manager** for secure shell access without needing SSH keys.

-----

## Manual Configuration Steps

### Step 1: Access the Vault Server and Set Environment Variable

1.  **Connect:** Access the Vault EC2 instance via AWS Console --> EC2 --> Instances --> Select Vault Instance --> Actions --> Connect --> Session Manager --> Connect.

2.  **Set `VAULT_ADDR`:** Once connected, set the local address for the Vault API.

    ```bash
    export VAULT_ADDR='http://127.0.0.1:8200'
    ```

    > **Note:** For commands run locally on the server where Vault binds to `localhost`, this address is correct. If running remotely, use the appropriate internal IP or DNS.

### Step 2: Initialize Vault (One-Time Operation)

This command must be run only once in the entire lifecycle of this Vault cluster. It generates the security keys.

```bash
vault operator init
```

> **⚠️ CRITICAL SECURITY ACTION:**
>
> **Immediately and securely save the following output:**
>
> 1.  All 5 **Recovery Key** values (required for disaster recovery if auto-unseal fails).
> 2.  The **Initial Root Token** (required for the first login to perform configuration).
>
> **Do not store these artifacts in plaintext or on the server itself.** They should be stored in a secure, offline secrets vault, or according to your organization's key management policy.

### Step 3: Log In to Vault with the Root Token

Use the Initial Root Token obtained in the previous step to log in and gain administrative privileges. This allows you to configure Vault before handing control over to Jenkins for automation.

```bash
vault login <YOUR_INITIAL_ROOT_TOKEN>
```

> **Result:** The Vault CLI is now authenticated with **root privileges**. The server is ready to be configured with authentication methods and policies by the automated Jenkins pipeline.

-----

## Project Phase Summary

| Phase | Tool | Action | Output |
| :--- | :--- | :--- | :--- |
| **1 (Setup Script)** | Bash/Terraform | Deploys AWS infrastructure (VPC, Vault EC2, Jenkins EC2). | Running Vault instance. |
| **Bridge (Manual)** | CLI | **Initialize Vault** and retrieve Root Token/Recovery Keys. | Initial Root Token (saved as a Jenkins Secret). |
| **2 (Jenkinsfile)** | Jenkins/Terraform | Automate creation of Vault policies, roles, and client servers (Sonarqube, etc.). | Full application environment deployed and secured via Vault. |