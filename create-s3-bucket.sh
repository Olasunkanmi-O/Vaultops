#!/bin/bash
set -e  # Stop script if any command fails

# --- Variables ---
BUCKET_NAME="pet-bucket-new"
AWS_REGION="us-east-2"
AWS_PROFILE="ola-devops"
INFRA_TERRAFORM_DIR="jenkins-vault"       

#defining ansible path
LOCAL_ANSIBLE_PROJECT_DIR="./module/ansible/ansible-project" # <--- ADJUST THIS PATH
S3_ANSIBLE_PREFIX="ansible-code/latest/"


echo "=== AWS Profile: $AWS_PROFILE ==="
echo "=== AWS Region:  $AWS_REGION ==="
echo "=== S3 Bucket:   $BUCKET_NAME ==="

# --- Check if bucket already exists ---
echo "Checking if bucket exists..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
  echo " Bucket '$BUCKET_NAME' already exists. Skipping creation."
else
  echo " Bucket not found. Creating bucket..."

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

  echo " Bucket '$BUCKET_NAME' created."
fi

# --- Enable versioning ---
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --versioning-configuration Status=Enabled
echo " Versioning enabled."

# --- Enable default encryption ---
echo "Enabling server-side encryption..."
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
echo " Encryption enabled."

#--- upload initial ansible folders to s3 bucket ----#
echo "Uploading initial Ansible code to S3 bucket..."
# Ensure the local directory exists before attempting to sync
if [ ! -d "$LOCAL_ANSIBLE_PROJECT_DIR" ]; then
    echo "ERROR: Local Ansible project directory '${LOCAL_ANSIBLE_PROJECT_DIR}' not found!"
    echo "Please ensure your Ansible project is located at this path relative to the script."
    exit 1
fi
aws s3 sync "${LOCAL_ANSIBLE_PROJECT_DIR}" "s3://${BUCKET_NAME}/${S3_ANSIBLE_PREFIX}" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"

echo "Initial Ansible code uploaded to s3://${BUCKET_NAME}/${S3_ANSIBLE_PREFIX}"


# --- Deploy Jenkins and Vault Infrastructure ---
echo " Deploying Jenkins and vault Infrastructure..."
cd "$INFRA_TERRAFORM_DIR"
echo "INFO: Initializing Terraform for infrastructure..."
terraform init 

if ! terraform apply -auto-approve; then
    echo "CRITICAL ERROR: 'terraform apply' for infrastructure failed!"
    echo "Please check the Terraform output above for details."
    exit 1
fi
echo "INFO: Jenkins and Vault AWS Infrastructure deployed."
