# Data source to reference the *existing* S3 bucket
data "aws_s3_bucket" "shared_bucket_data" {
  bucket = "pet-bucket-new"
}

# --- Null Resource to Trigger S3 Sync of Ansible Code ---
resource "null_resource" "sync_ansible_code_to_s3" {
  # The 'triggers' block is crucial. It tells Terraform *when* to re-run
  # the local-exec provisioner. By hashing the content of the entire
  # 'ansible' directory, the provisioner will re-run only when
  # any file within that directory changes.
  triggers = {
    # This creates a hash based on the content of all files in the 'ansible' directory.
    # Adjust the 'path.module/ansible' to your actual local Ansible project path.
    dir_hash = sha1(join("", [for f in fileset("${path.module}/ansible", "**") : filemd5("${path.module}/ansible/${f}")]))
  }

  provisioner "local-exec" {
    # The command to execute locally.
    # It uses 'aws s3 sync' to synchronize the local 'ansible' directory
    # with the 'ansible-code/latest/' prefix in your S3 bucket.
    #
    # --delete: Deletes files in S3 that no longer exist locally.
    # --exclude ".git/*": Excludes the .git directory (and its contents) from syncing.
    # --exclude ".*": Excludes all hidden files/directories (like .terraform, .DS_Store, etc.)
    command = "aws s3 sync ${path.module}/ansible/ s3://${data.aws_s3_bucket.shared_bucket_data.id}/ansible-code/latest/ --delete --exclude '.git/*' --exclude '.*'"

    # The working_directory for the command.
    # Using path.module ensures it runs relative to your Terraform module.
    #working_directory = ${path.module}

    # You can add environment variables if your aws cli needs specific config,
    # though it generally picks up from standard AWS CLI config or env vars.
    # environment = {
    #   AWS_REGION = "eu-west-2"
    # }
  }

  # Add an explicit dependency if you want this to run after certain
  # resources (like the S3 bucket itself, if it were provisioned here,
  # or after network setup if that's relevant to the machine running Terraform).
  # In your case, the bucket already exists, so no direct dependency might be needed
  # on the bucket resource itself.
  # depends_on = [
  #   some_other_resource_that_must_exist_first.id
  # ]
}