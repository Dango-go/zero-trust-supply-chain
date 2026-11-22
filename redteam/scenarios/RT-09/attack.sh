#!/usr/bin/env bash
set -uo pipefail

# RT-09: Arbitrary Egress Exfiltration & GCP Metadata Server Access Test
# Expected: Both https://example.org and 169.254.169.254:80 are dropped by Cilium eBPF.

APP_NS="${APP_NS:-zt-apps}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-09 requires a reachable Kubernetes cluster with Cilium and zt-apps deployed."
  exit 1
fi

PAYMENTS_POD="$(kubectl -n "${APP_NS}" get pods -l app.kubernetes.io/name=zt-payments -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${PAYMENTS_POD}" ]]; then
  echo "[ERROR] No running zt-payments pod found in namespace '${APP_NS}'."
  exit 1
fi

echo "==> [RT-09] Using source pod: ${PAYMENTS_POD} in ${APP_NS}"

echo "==> [RT-09] 1. Attempting unauthorized egress to https://example.org..."
EXT_OUT="$(kubectl -n "${APP_NS}" exec "${PAYMENTS_POD}" -- python -c "
import urllib.request, sys
try:
    with urllib.request.urlopen('https://example.org', timeout=4) as r:
        print('UNEXPECTED_STATUS=' + str(r.status))
        sys.exit(1)
except Exception as e:
    print('BLOCKED_AS_EXPECTED=' + str(e))
    sys.exit(0)
" 2>&1)"
EXT_RC=$?
echo "External egress output: ${EXT_OUT}"

if [[ ${EXT_RC} -ne 0 ]]; then
  echo "[FAIL] RT-09: Unauthorized egress to https://example.org succeeded!"
  exit 1
fi

echo "==> [RT-09] 2. Attempting GCP Metadata Server access (169.254.169.254:80)..."
META_OUT="$(kubectl -n "${APP_NS}" exec "${PAYMENTS_POD}" -- python -c "
import urllib.request, sys
req = urllib.request.Request('http://169.254.169.254/computeMetadata/v1/', headers={'Metadata-Flavor': 'Google'})
try:
    with urllib.request.urlopen(req, timeout=4) as r:
        print('UNEXPECTED_METADATA_STATUS=' + str(r.status))
        sys.exit(1)
except Exception as e:
    print('BLOCKED_AS_EXPECTED=' + str(e))
    sys.exit(0)
" 2>&1)"
META_RC=$?
echo "Metadata probe output: ${META_OUT}"

if [[ ${META_RC} -ne 0 ]]; then
  echo "[FAIL] RT-09: Access to GCP Metadata server 169.254.169.254 succeeded!"
  exit 1
fi

echo "[PASS] RT-09 blocked arbitrary egress and GCP metadata SSRF via Cilium eBPF."
exit 0
