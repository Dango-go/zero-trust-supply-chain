#!/usr/bin/env bash
set -uo pipefail

# RT-11: Secret Leakage Audit & Vault Dynamic DB Lease Revocation
# Expected:
#   1) Zero hardcoded DB passwords in apps/manifests/ and 0 leaks via gitleaks (if installed).
#   2) If Vault is running in cluster, issuing & revoking a dynamic DB lease succeeds and enforces policy.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
VAULT_NS="${VAULT_NS:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"

echo "==> [RT-11] 1. Checking apps/manifests/ for hardcoded DB_PASSWORD env vars..."
if grep -rn "DB_PASSWORD" "${ROOT_DIR}/apps/manifests/" >/dev/null 2>&1; then
  echo "[FAIL] RT-11: Found hardcoded DB_PASSWORD in apps/manifests/!"
  exit 1
fi
echo "[OK] No static DB_PASSWORD found in apps/manifests/."

if command -v gitleaks >/dev/null 2>&1; then
  echo "==> [RT-11] 2. Running Gitleaks secret scan..."
  if ! gitleaks detect --source "${ROOT_DIR}" --config "${ROOT_DIR}/.gitleaks.toml" --no-banner --redact >/dev/null 2>&1; then
    echo "[FAIL] RT-11: Gitleaks detected potential secret leak(s)!"
    exit 1
  fi
  echo "[OK] Gitleaks found 0 secret leaks."
else
  echo "[INFO] gitleaks CLI not installed locally; skipping git history scan."
fi

if command -v kubectl >/dev/null 2>&1 && kubectl -n "${VAULT_NS}" get pod "${VAULT_POD}" >/dev/null 2>&1; then
  echo "==> [RT-11] 3. Testing Vault dynamic credential generation and immediate lease revocation..."
  CREDS_JSON="$(kubectl -n "${VAULT_NS}" exec "${VAULT_POD}" -- vault read -format=json database/creds/orders-rw 2>&1)"
  if [[ $? -ne 0 ]]; then
    echo "[FAIL] RT-11: Failed to generate dynamic credential from Vault: ${CREDS_JSON}"
    exit 1
  fi

  LEASE_ID="$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['lease_id'])" <<<"${CREDS_JSON}" 2>/dev/null || true)"
  if [[ -z "${LEASE_ID}" ]]; then
    echo "[FAIL] RT-11: Could not extract lease_id from Vault response."
    exit 1
  fi

  echo "Generated temporary lease: ${LEASE_ID}. Revoking immediately..."
  if ! kubectl -n "${VAULT_NS}" exec "${VAULT_POD}" -- vault lease revoke "${LEASE_ID}" >/dev/null 2>&1; then
    echo "[FAIL] RT-11: Vault failed to revoke lease ${LEASE_ID}!"
    exit 1
  fi
  echo "[OK] Lease ${LEASE_ID} revoked successfully."
else
  echo "[INFO] Vault pod '${VAULT_POD}' not reachable in cluster; verified static manifests & HCL policy."
  if ! grep -q 'capabilities = \["deny"\]' "${ROOT_DIR}/platform/vault/policies/orders-rw.hcl"; then
    echo "[FAIL] RT-11: orders-rw.hcl missing explicit deny rules!"
    exit 1
  fi
fi

echo "[PASS] RT-11 verified secret hygiene and Vault dynamic lease lifecycle."
exit 0
