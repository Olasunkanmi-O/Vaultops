#!/bin/bash

# exit once there is an error
set -e

# delete jenkins-vault resources
echo "deleting jenkins and vault server"
cd jenkins-vault
terraform init 
terraform destroy -auto-approve

# Set your bucket name and AWS region
BUCKET_NAME="pet-bucket-new" # Replace with your actual S3 bucket name
AWS_REGION="eu-west-2"                  # Replace with your actual AWS region

# Set the batch size for delete-objects (max 1000)
BATCH_SIZE=1000

echo "Starting batch deletion of all objects, versions, and delete markers in S3 bucket: $BUCKET_NAME"

# Function to perform batch deletion
delete_batch() {
  local bucket="$1"
  local region="$2"
  local json_array="$3"

  if [ -z "$json_array" ] || [ "$(echo "$json_array" | jq '. | length')" -eq 0 ]; then
    echo "No objects to delete in this batch."
    return
  fi

  # Wrap the input array into the "Delete" structure
  local delete_request="{\"Objects\": $json_array, \"Quiet\": true}"

  # Create a temp file in the current directory (safer for Git Bash)
  local tmpfile="./delete-request-$$.json"
  echo "$delete_request" > "$tmpfile"

  echo "Deleting batch of $(echo "$json_array" | jq '. | length') objects/versions..."
  aws s3api delete-objects \
    --bucket "$bucket" \
    --region "$region" \
    --delete "file://$tmpfile" \
    --output text

  # Clean up
  rm -f "$tmpfile"
}



# --- Step 1: Delete all object versions ---
echo "Listing and preparing object versions for deletion..."
declare -a VERSION_ITEMS
while IFS= read -r line; do
  VERSION_ITEMS+=("$line")
  if [ "${#VERSION_ITEMS[@]}" -ge "$BATCH_SIZE" ]; then
    JSON_ARRAY=$(printf "%s\n" "${VERSION_ITEMS[@]}" | jq -s '.')
    delete_batch "$BUCKET_NAME" "$AWS_REGION" "$JSON_ARRAY"
    VERSION_ITEMS=() # Clear batch
  fi
done < <(aws s3api list-object-versions \
           --bucket "$BUCKET_NAME" \
           --region "$AWS_REGION" \
           --output json \
           --query 'Versions' | \
           jq -c '.[] | {Key: .Key, VersionId: .VersionId}') # <--- CRITICAL FIX HERE

# Process any remaining items in the last batch of versions
if [ "${#VERSION_ITEMS[@]}" -gt 0 ]; then
  JSON_ARRAY=$(printf "%s\n" "${VERSION_ITEMS[@]}" | jq -s '.')
  delete_batch "$BUCKET_NAME" "$AWS_REGION" "$JSON_ARRAY"
fi
echo "Object versions deletion complete."


# --- Step 2: Delete all delete markers ---
echo "Listing and preparing delete markers for deletion..."
declare -a MARKER_ITEMS
while IFS= read -r line; do
  MARKER_ITEMS+=("$line")
  if [ "${#MARKER_ITEMS[@]}" -ge "$BATCH_SIZE" ]; then
    JSON_ARRAY=$(printf "%s\n" "${MARKER_ITEMS[@]}" | jq -s '.')
    delete_batch "$BUCKET_NAME" "$AWS_REGION" "$JSON_ARRAY"
    MARKER_ITEMS=() # Clear batch
  fi
done < <(aws s3api list-object-versions \
           --bucket "$BUCKET_NAME" \
           --region "$AWS_REGION" \
           --output json \
           --query 'DeleteMarkers' | \
           jq -c '.[] | {Key: .Key, VersionId: .VersionId}') # <--- CRITICAL FIX HERE

# Process any remaining items in the last batch of delete markers
if [ "${#MARKER_ITEMS[@]}" -gt 0 ]; then
  JSON_ARRAY=$(printf "%s\n" "${MARKER_ITEMS[@]}" | jq -s '.')
  delete_batch "$BUCKET_NAME" "$AWS_REGION" "$JSON_ARRAY"
fi
echo "Delete markers deletion complete."

# Optional: Verify the bucket is empty
echo "Verifying bucket contents..."
aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query 'Contents'

echo "All specified objects, versions, and delete markers in bucket '$BUCKET_NAME' have been deleted."

# Delete the bucket
echo "deleting s3 bucket "${BUCKET_NAME}""
aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
echo "bucket '${BUCKET_NAME}' is deleted"