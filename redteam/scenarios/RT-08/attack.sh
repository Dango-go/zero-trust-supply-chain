#!/usr/bin/env bash
set -uo pipefail

# RT-08: Lateral Movement & Cilium L7 HTTP Policy Bypass Test
# Expected:
#   1) Unauthorized HTTP path on zt-payments (/docs) returns HTTP 403 via Cilium L7.
#   2) Outbound connection to unauthorized namespace (vault:8200) is dropped/timed out.

APP_NS="${APP_NS:-zt-apps}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-08 requires a reachable Kubernetes cluster with Cilium and zt-apps deployed."
  exit 1
fi

ORDERS_POD="$(kubectl -n "${APP_NS}" get pods -l app.kubernetes.io/name=zt-orders -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${ORDERS_POD}" ]]; then
  echo "[ERROR] No running zt-orders pod found in namespace '${APP_NS}'."
  exit 1
fi

echo "==> [RT-08] Using source pod: ${ORDERS_POD} in ${APP_NS}"

echo "==> [RT-08] 1. Testing Cilium L7 HTTP enforcement (forbidden GET /docs -> zt-payments:8080)..."
L7_OUT="$(kubectl -n "${APP_NS}" exec "${ORDERS_POD}" -- python -c "
import urllib.request, urllib.error, sys
try:
    with urllib.request.urlopen('http://zt-payments.zt-apps.svc.cluster.local:8080/docs', timeout=5) as r:
        print('HTTP_CODE=' + str(r.status))
        sys.exit(2)
except urllib.error.HTTPError as e:
    print('HTTP_CODE=' + str(e.code))
    sys.exit(0 if e.code == 403 else 1)
except Exception as e:
    print('ERR=' + str(e))
    sys.exit(1)
" 2>&1)"
L7_RC=$?
echo "L7 probe output: ${L7_OUT}"

if [[ ${L7_RC} -ne 0 ]]; then
  echo "[FAIL] RT-08: Cilium L7 policy did NOT return 403 for unauthorized path /docs!"
  exit 1
fi

echo "==> [RT-08] 2. Testing cross-namespace egress block (zt-orders -> vault.vault.svc.cluster.local:8200)..."
EGRESS_OUT="$(kubectl -n "${APP_NS}" exec "${ORDERS_POD}" -- python -c "
import socket, sys
s = socket.socket()
s.settimeout(4)
try:
    s.connect(('vault.vault.svc.cluster.local', 8200))
    print('CONNECTED_UNEXPECTEDLY')
    sys.exit(1)
except Exception as e:
    print('BLOCKED_AS_EXPECTED=' + str(e))
    sys.exit(0)
" 2>&1)"
EGRESS_RC=$?
echo "Cross-namespace probe output: ${EGRESS_OUT}"

if [[ ${EGRESS_RC} -ne 0 ]]; then
  echo "[FAIL] RT-08: Unauthorized cross-namespace connection to Vault succeeded!"
  exit 1
fi

if command -v hubble >/dev/null 2>&1; then
  echo "==> [RT-08] Checking Hubble dropped flows..."
  hubble observe --namespace "${APP_NS}" --verdict DROPPED --last 5 || true
fi

echo "[PASS] RT-08 blocked by Cilium L7 HTTP policy and default-deny egress."
exit 0
