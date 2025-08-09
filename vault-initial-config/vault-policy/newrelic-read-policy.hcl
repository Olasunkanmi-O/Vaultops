# This policy grants read access to the New Relic credentials
path "secret/data/newrelic" {
  capabilities = ["read"]
}