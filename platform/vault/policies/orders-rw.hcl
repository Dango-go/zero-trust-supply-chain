# Allow reading dynamic, short-lived credentials for PostgreSQL
path "database/creds/orders-rw" {
  capabilities = ["read"]
}

# Explicitly deny access to any other sensitive Vault paths
path "secret/*" {
  capabilities = ["deny"]
}

path "sys/*" {
  capabilities = ["deny"]
}
