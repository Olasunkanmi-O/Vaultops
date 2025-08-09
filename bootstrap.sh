#!/bin/bash
set -euo pipefail 

# --- Global Variables ---
LOG_FILE="/var/log/bootstrapping_$(date +%Y%m%d%H%M%S)_$$_$(hostname).log"
SCRIPT_NAME=$(basename "$0")

# --- Default Configuration Variables (can be overridden by args/env) ---
BUCKET_NAME="pet-bucket-new25"
AWS_REGION="us-east-2"
AWS_PROFILE="ola-devops"

# Terraform directories for each stage
INFRA_TERRAFORM_DIR="jenkins-vault" # This is where your AWS infra code lives
VAULT_CONFIG_TERRAFORM_DIR="vault-initial-config" # This is where your initial Vault config code lives

# Terraform state key for the infrastructure phase
INFRA_TERRAFORM_STATE_KEY="infrastructure/terraform.tfstate"

# --- Logging Functions ---
log() {
    local level="$1"
    local message="$2"
    printf "[%s] [%s] %s: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$SCRIPT_NAME" "$message" | tee -a "$LOG_FILE" >&2
}
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Trap for Cleanup on Exit/Error ---
cleanup() {
    local exit_code=$? # Capture the exit code of the last command
    log_info "--- Script Exiting ---"
    log_info "Exit code: $exit_code"

    # Check for lock in the *infrastructure* Terraform directory
    if [[ -d "$INFRA_TERRAFORM_DIR" ]]; then
        pushd "$INFRA_TERRAFORM_DIR" > /dev/null || true
        log_info "Checking infrastructure Terraform lock status..."
        if terraform plan -lock-timeout=0s 2>&1 | grep -q "Error acquiring the state lock"; then
            log_error "********************************************************************************"
            log_error "ERROR: Infrastructure Terraform state appears to be locked!"
            log_error "To resolve: cd $INFRA_TERRAFORM_DIR && terraform force-unlock <LOCK_ID>"
            log_error "********************************************************************************"
        fi
        popd > /dev/null || true
    fi

    # Check for lock in the *Vault config* Terraform directory
    if [[ -d "$VAULT_CONFIG_TERRAFORM_DIR" ]]; then
        pushd "$VAULT_CONFIG_TERRAFORM_DIR" > /dev/null || true
        log_info "Checking Vault config Terraform lock status..."
        if terraform plan -lock-timeout=0s 2>&1 | grep -q "Error acquiring the state lock"; then
            log_error "********************************************************************************"
            log_error "ERROR: Vault config Terraform state appears to be locked!"
            log_error "To resolve: cd $VAULT_CONFIG_TERRAFORM_DIR && terraform force-unlock <LOCK_ID>"
            log_error "********************************************************************************"
        fi
        popd > /dev/null || true
    fi
    log_info "--- Cleanup Complete ---"
}
trap cleanup EXIT INT TERM

# --- Function for Argument Parsing ---
parse_args() {
    while getopts "b:r:p:" opt; do
        case ${opt} in
            b ) BUCKET_NAME=$OPTARG ;;
            r ) AWS_REGION=$OPTARG ;;
            p ) AWS_PROFILE=$OPTARG ;;
            \? ) usage ;;
        esac
    done
    shift $((OPTIND -1))

    if [[ -z "$BUCKET_NAME" || -z "$AWS_REGION" || -z "$AWS_PROFILE" ]]; then
        usage
    fi
}
usage() {
    log_error "Usage: $0 [-b BUCKET_NAME] [-r AWS_REGION] [-p AWS_PROFILE]"
    log_error "Default values: BUCKET_NAME='${BUCKET_NAME}', AWS_REGION='${AWS_REGION}', AWS_PROFILE='${AWS_PROFILE}'"
    exit 1
}

# --- Core Functions ---
check_dependencies() {
    log_info "Checking required dependencies..."
    local deps=("aws" "terraform" "curl") # Add curl for Vault health check
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required command '$dep' not found. Please install it and ensure it's in your PATH."
            exit 1
        fi
    done
    log_info "All dependencies found."
}

create_s3_bucket() {
    log_info "Checking if bucket '$BUCKET_NAME' exists..."
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
        log_info "Bucket '$BUCKET_NAME' already exists. Skipping creation."
    else
        log_info "Bucket '$BUCKET_NAME' not found. Creating bucket..."
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE"
        else
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        log_info "Bucket '$BUCKET_NAME' created."
    fi
}

configure_s3_bucket() {
    log_info "Enabling versioning for bucket '$BUCKET_NAME'..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --versioning-configuration Status=Enabled
    log_info "Versioning enabled."

    log_info "Enabling server-side encryption for bucket '$BUCKET_NAME'..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    log_info "Encryption enabled."
}

wait_for_vault_ready() {
    local vault_addr="$1"
    log_info "Waiting for Vault at ${vault_addr} to be ready and unsealed..."
    local max_attempts=60 # Try for 10 minutes (60 * 10 seconds)
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt ${attempt}/${max_attempts} to reach Vault health endpoint..."
        # Using -L for follow redirects
        # Using --max-time to ensure curl doesn't hang indefinitely
        HEALTH_STATUS=$(curl -s -k -L --fail --max-time 10 "${vault_addr}/v1/sys/health" || true)
        if echo "$HEALTH_STATUS" | grep -q '"initialized":true' && \
           echo "$HEALTH_STATUS" | grep -q '"sealed":false'; then
            log_info "Vault is initialized and unsealed!"
            return 0
        else
            log_info "Vault not ready yet. Status: ${HEALTH_STATUS:-Not reachable}. Waiting 10 seconds..."
            sleep 10
        fi
        attempt=$((attempt+1))
    done

    log_error "Vault did not become ready and unsealed within the expected time."
    return 1
}


# --- Main Execution Flow ---
log_info "Starting bootstrapping process..."

parse_args "$@"
log_info "AWS Profile: $AWS_PROFILE"
log_info "AWS Region:  $AWS_REGION"
log_info "S3 Bucket:   $BUCKET_NAME"

check_dependencies

create_s3_bucket
configure_s3_bucket

# --- Phase 1: Deploy Jenkins and Vault AWS Infrastructure ---
log_info "--- Phase 1: Deploying Jenkins and Vault AWS Infrastructure ---"
log_info "Changing directory to Terraform infrastructure project: '$INFRA_TERRAFORM_DIR'..."
pushd "$INFRA_TERRAFORM_DIR" || { log_error "Could not change to $INFRA_TERRAFORM_DIR. Exiting."; exit 1; }

log_info "Initializing Terraform for infrastructure..."
terraform init \
    -backend-config="bucket=$BUCKET_NAME" \
    -backend-config="key=$INFRA_TERRAFORM_STATE_KEY" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="profile=$AWS_PROFILE" \
    -backend-config="use_lockfile=true"

log_info "Terraform infrastructure initialized."
log_info "Validating Terraform infrastructure configuration..."
terraform validate
log_info "Terraform infrastructure configuration validated."

log_info "Applying Terraform infrastructure changes (auto-approve)..."
if ! terraform apply -auto-approve; then
    log_error "CRITICAL ERROR: 'terraform apply' for infrastructure failed!"
    log_error "Please check the Terraform output above for details."
    popd || true # Attempt to return to original directory even on error
    exit 1
fi
log_info "Jenkins and Vault AWS Infrastructure deployed."

# Get Vault ELB URL and MySQL Host from outputs of Phase 1
VAULT_URL=$(terraform output -raw vault_url)
# VAULT_ELB_DNS_NAME=$(terraform output -raw vault_elb_dns_name) # If you need just the DNS name
MYSQL_HOST=$(terraform output -raw mysql_host)
MYSQL_PORT=$(terraform output -raw mysql_port)

popd # Return to original directory

# --- Get Vault Root Token (Crucial Manual/Semi-Automated Step) ---
# IMPORTANT: For initial Vault setup, you need a root token.
# This is often done:
# 1. Manually by SSHing to Vault and running 'vault operator init'
# 2. Or, if user_data generates one-time token and pushes to SSM, retrieve it here.
# For this script to work, you MUST set VAULT_ROOT_TOKEN in your environment.
if [[ -z "${VAULT_ROOT_TOKEN}" ]]; then
    log_error "VAULT_ROOT_TOKEN environment variable is not set."
    log_error "You must obtain a Vault root token (e.g., from initial unseal, if user_data doesn't handle it securely)."
    log_error "Set 'export VAULT_ROOT_TOKEN=<your-token>' before running this script."
    exit 1
fi

# Wait for Vault to be ready and unsealed before proceeding with configuration
wait_for_vault_ready "$VAULT_URL" || exit 1 # Exit if Vault not ready

# --- Phase 2: Configure Initial Vault Setup (Policies, AppRoles, KV secrets) ---
log_info "--- Phase 2: Configuring Initial Vault Setup ---"
log_info "Changing directory to Vault configuration project: '$VAULT_CONFIG_TERRAFORM_DIR'..."
pushd "$VAULT_CONFIG_TERRAFORM_DIR" || { log_error "Could not change to $VAULT_CONFIG_TERRAFORM_DIR. Exiting."; exit 1; }

log_info "Initializing Terraform for Vault configuration..."
# Assuming no separate backend for this stage, or it has its own in its backend.tf
terraform init

log_info "Terraform Vault configuration initialized."
log_info "Validating Terraform Vault configuration..."
terraform validate
log_info "Terraform Vault configuration validated."

log_info "Applying Terraform Vault configuration changes (auto-approve)..."
# Pass all required variables to the Vault config Terraform
if ! terraform apply \
    -auto-approve \
    -var="vault_address=${VAULT_URL}" \
    -var="vault_token=${VAULT_ROOT_TOKEN}" \
    -var="newrelic_api_key=${NEWRELIC_API_KEY:-}" \
    -var="newrelic_user_id=${NEWRELIC_USER_ID:-}" \
    -var="domain_name=${DOMAIN_NAME:-}" ; then
    log_error "CRITICAL ERROR: 'terraform apply' for Vault initial configuration failed!"
    log_error "Please check the Terraform output above for details."
    popd || true
    exit 1
fi
log_info "Vault initial configuration deployed."

popd # Return to original directory

log_info "Bootstrapping process completed successfully for Phase 1 & 2!"
log_info "Phase 3 (Vault Database Configuration) should now be triggered from Jenkins, passing MySQL host: ${MYSQL_HOST} and Vault URL: ${VAULT_URL}"