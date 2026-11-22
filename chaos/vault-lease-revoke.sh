#!/usr/bin/env bash
set -euo pipefail

VAULT_NS="${VAULT_NS:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
APP_NS="${APP_NS:-zt-apps}"
APP_DEPLOY="${APP_DEPLOY:-zt-orders}"
LEASE_PREFIX="${LEASE_PREFIX:-database/creds/orders-rw}"

echo "==> [1/4] Checking $APP_DEPLOY readiness before lease revocation..."
kubectl -n "$APP_NS" rollout status deploy/"$APP_DEPLOY" --timeout=60s

echo "==> [2/4] Revoking active Vault leases with prefix '$LEASE_PREFIX'..."
kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- vault lease revoke -prefix "$LEASE_PREFIX"

echo "==> [3/4] Waiting for $APP_DEPLOY to handle revoked credentials and stay/become Ready..."
sleep 5
kubectl -n "$APP_NS" wait --for=condition=Ready pod -l app="$APP_DEPLOY" --timeout=120s

echo "==> [4/4] Chaos test vault-lease-revoke PASSED."
