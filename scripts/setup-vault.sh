#!/usr/bin/env bash
# Setup & Configure HashiCorp Vault HA on GKE
# - Initializes and unseals Vault (if needed)
# - Configures Kubernetes Auth method for 'zt-apps' namespace & 'zt-orders-sa'
# - Applies least-privilege policies ('orders-rw')
# - Configures PostgreSQL Database Secrets Engine for dynamic credentials


set -euo pipefail

VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
APP_NAMESPACE="${APP_NAMESPACE:-zt-apps}"
DB_NAMESPACE="${DB_NAMESPACE:-zt-data}"
VAULT_POD="${VAULT_POD:-vault-0}"

 
echo " Starting HashiCorp Vault Zero-Trust Configuration..."

# Helper function to execute Vault CLI inside the vault-0 pod
v_exec() {
  kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- vault "$@"
}

echo "==> [1/6] Checking Vault initialization and seal status..."
INIT_STATUS=$(kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- vault status -format=json 2>/dev/null || true)

INITIALIZED=$(echo "${INIT_STATUS}" | grep -o '"initialized":[^,]*' | cut -d: -f2 | tr -d ' ' || echo "false")
SEALED=$(echo "${INIT_STATUS}" | grep -o '"sealed":[^,]*' | cut -d: -f2 | tr -d ' ' || echo "true")

if [[ "${INITIALIZED}" != "true" ]]; then
  echo "==> Initializing Vault Raft cluster (saving keys locally)..."
  INIT_OUTPUT=$(kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- vault operator init -key-shares=5 -key-threshold=3 -format=json)
  
  # Save unseal keys and root token securely to .vault-init.json (gitignored)
  echo "${INIT_OUTPUT}" > .vault-init.json
  chmod 600 .vault-init.json
  echo "Keys and root token saved to .vault-init.json"

  UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' .vault-init.json)
  UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' .vault-init.json)
  UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' .vault-init.json)
  ROOT_TOKEN=$(jq -r '.root_token' .vault-init.json)

  echo "==> Unsealing vault-0..."
  v_exec operator unseal "${UNSEAL_KEY_1}"
  v_exec operator unseal "${UNSEAL_KEY_2}"
  v_exec operator unseal "${UNSEAL_KEY_3}"
else
  echo "Vault is already initialized."
  if [[ "${SEALED}" == "true" ]]; then
    if [[ ! -f .vault-init.json ]]; then
      echo "ERROR: Vault is sealed but .vault-init.json not found! Cannot automatically unseal."
      exit 1
    fi
    echo "==> Unsealing vault-0 using .vault-init.json..."
    UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' .vault-init.json)
    UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' .vault-init.json)
    UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' .vault-init.json)
    v_exec operator unseal "${UNSEAL_KEY_1}"
    v_exec operator unseal "${UNSEAL_KEY_2}"
    v_exec operator unseal "${UNSEAL_KEY_3}"
  fi
  ROOT_TOKEN=$(jq -r '.root_token' .vault-init.json)
fi

echo "==> Logging in with root token inside pod..."
kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- vault login -no-print "${ROOT_TOKEN}"

echo "==> [2/6] Enabling Kubernetes Auth Engine..."
kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- /bin/sh -c '
  vault auth enable kubernetes 2>/dev/null || echo "Kubernetes auth already enabled"
  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc"
'

echo "==> [3/6] Applying Least-Privilege HCL Policy (orders-rw)..."
kubectl cp platform/vault/policies/orders-rw.hcl "${VAULT_NAMESPACE}/${VAULT_POD}:/tmp/orders-rw.hcl"
v_exec policy write orders-rw /tmp/orders-rw.hcl

echo "==> [4/6] Binding Kubernetes Auth Role for zt-orders ServiceAccount..."
v_exec write auth/kubernetes/role/orders-role \
  bound_service_account_names=zt-orders-sa \
  bound_service_account_namespaces="${APP_NAMESPACE}" \
  policies=orders-rw \
  ttl=1h

echo "==> [5/6] Enabling Database Secrets Engine..."
kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- /bin/sh -c '
  vault secrets enable database 2>/dev/null || echo "Database secrets engine already enabled"
'

echo "==> Fetching PostgreSQL credentials from CloudNativePG secret..."
# CloudNativePG generates <cluster-name>-app secret with owner password
DB_PASSWORD=$(kubectl get secret postgres-app -n "${DB_NAMESPACE}" -o jsonpath='{.data.password}' | base64 --decode)
DB_USER=$(kubectl get secret postgres-app -n "${DB_NAMESPACE}" -o jsonpath='{.data.user}' | base64 --decode)
DB_HOST="postgres-rw.${DB_NAMESPACE}.svc.cluster.local"

echo "==> Configuring PostgreSQL connection in Vault..."
v_exec write database/config/postgresql \
  plugin_name=postgresql-database-plugin \
  allowed_roles=orders-rw \
  connection_url="postgresql://{{username}}:{{password}}@${DB_HOST}:5432/orders?sslmode=disable" \
  username="${DB_USER}" \
  password="${DB_PASSWORD}"

echo "==> [6/6] Creating Dynamic Role for orders-rw with 1h TTL (Zero-Trust)..."
v_exec write database/roles/orders-rw \
  db_name=postgresql \
  default_ttl=1h \
  max_ttl=24h \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
                       GRANT CONNECT ON DATABASE orders TO \"{{name}}\"; \
                       GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
                       GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_statements="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '{{name}}'; \
                         DROP ROLE IF EXISTS \"{{name}}\";"


echo " SUCCESS! HashiCorp Vault is fully configured for Zero-Trust Dynamic DB Creds!"
echo " ServiceAccount: zt-orders-sa -> Role: orders-role -> Policy: orders-rw"
 
