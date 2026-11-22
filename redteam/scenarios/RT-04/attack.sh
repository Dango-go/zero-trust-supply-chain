#!/usr/bin/env bash
set -uo pipefail

# RT-04: Replay attack using a previously signed but now revoked (or stale) image digest.
# Expected: Kyverno admission webhook rejects the Pod via 'deny-revoked-digests' (or 'verify-images' freshness).

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt04-revoked-digest-pod.yaml"

REGISTRY_URL="${REGISTRY_URL:-europe-west1-docker.pkg.dev/security-supply-chain/zero-trust}"
RT04_IMAGE="${RT04_IMAGE:-${REGISTRY_URL}/zt-orders@sha256:0000000000000000000000000000000000000000000000000000000000000000}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-04 requires a reachable Kubernetes cluster with Kyverno installed."
  exit 1
fi

echo "==> [RT-04] Attempting to deploy revoked/stale digest (replay): ${RT04_IMAGE}"
OUT="$(sed "s|\${RT04_IMAGE}|${RT04_IMAGE}|g" "${FIXTURE}" | kubectl apply -f - 2>&1)"
RC=$?

echo "${OUT}"

if [[ ${RC} -ne 0 ]] && grep -qE "deny-revoked-digests|verify-images" <<<"${OUT}"; then
  echo "[PASS] RT-04 replay attack blocked by Kyverno."
  exit 0
fi

echo "[FAIL] RT-04 was NOT blocked by 'deny-revoked-digests' or 'verify-images'!"
kubectl -n zt-apps delete pod rt04-revoked-digest-probe --ignore-not-found >/dev/null 2>&1 || true
exit 1
