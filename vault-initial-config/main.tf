resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "AppRole auth method"

  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
}

resource "vault_mount" "kv_secret" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "Key-Value secret engine v2"

  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
}

resource "vault_kv_secret_v2" "sonarqube_db" {
  mount = vault_mount.kv_secret.path
  name  = "sonarqube/db_credentials"

  data_json = jsonencode({
    username = var.sonarqube_db_username
    password = var.sonarqube_db_password
  })

  depends_on = [vault_mount.kv_secret]
}


# Consolidated policy for the applications to read both DB and New Relic secrets
resource "vault_policy" "app_read" {
  name   = "app-read-policy"
  policy = file("vault-policy/app-read-policy.hcl")
}

# Policy for the Ansible server to read New Relic secrets
resource "vault_policy" "newrelic_read" {
  name   = "newrelic-read-policy"
  policy = file("vault-policy/newrelic-read-policy.hcl")
}

# Policy for the sonarqube server to read New Relic secrets
resource "vault_policy" "sonarqube_read" {
  name   = "sonarqube-read-policy"
  policy = file("vault-policy/sonarqube-read-policy.hcl")
}

resource "vault_kv_secret_v2" "newrelic" {
  mount = vault_mount.kv_secret.path
  name  = "newrelic/api-key"

  data_json = jsonencode({
    api_key = var.newrelic_api_key
    user_id = var.newrelic_user_id
  })

  depends_on = [vault_mount.kv_secret]
}

resource "vault_kv_secret_v2" "petclinic_db" {
  mount = vault_mount.kv_secret.path
  name  = "petclinic/database/credentials"

  data_json = jsonencode({
    username = var.db_static_username
    password = var.db_static_password
  })

  depends_on = [vault_mount.kv_secret]
}

resource "vault_approle_auth_backend_role" "ansible_newrelic" {
  backend         = vault_auth_backend.approle.path
  role_name       = "ansible-newrelic-role"
  token_policies  = [vault_policy.newrelic_read.name]
  token_ttl       = 3600
  token_max_ttl   = 14400
  secret_id_ttl   = 86400

  depends_on = [
    vault_auth_backend.approle,
    vault_policy.newrelic_read
  ]
}

resource "vault_approle_auth_backend_role_secret_id" "ansible_newrelic_secret_id" {
  role_name = vault_approle_auth_backend_role.ansible_newrelic.role_name

  depends_on = [vault_approle_auth_backend_role.ansible_newrelic]
}

resource "vault_approle_auth_backend_role" "app_stage" {
  backend        = vault_auth_backend.approle.path
  role_name      = "stage-role"
  token_policies = [vault_policy.app_read.name]
  token_ttl      = 3600
  token_max_ttl  = 14400

  depends_on = [
    vault_auth_backend.approle,
    vault_policy.app_read
  ]
}

resource "vault_approle_auth_backend_role" "app_prod" {
  backend        = vault_auth_backend.approle.path
  role_name      = "prod-role"
  token_policies = [vault_policy.app_read.name]
  token_ttl      = 3600
  token_max_ttl  = 14400

  depends_on = [
    vault_auth_backend.approle,
    vault_policy.app_read
  ]
}

# Create a role for the SonarQube server to authenticate
resource "vault_approle_auth_backend_role" "sonarqube_read_role" {
  backend          = vault_auth_backend.approle.path
  role_name        = "sonarqube-read-role"
  token_policies   = [vault_policy.sonarqube_read.name]
  token_ttl        = 3600
  token_max_ttl    = 14400
  secret_id_ttl    = 86400

  depends_on = [
    vault_auth_backend.approle,
    vault_policy.sonarqube_read,
  ]
}

# Generate a secret ID for the SonarQube AppRole
resource "vault_approle_auth_backend_role_secret_id" "sonarqube_secret_id" {
  role_name = vault_approle_auth_backend_role.sonarqube_read_role.role_name
  depends_on = [vault_approle_auth_backend_role.sonarqube_read_role]
}