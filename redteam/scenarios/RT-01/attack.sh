#!/usr/bin/env bash
set -uo pipefail

# RT-01: Attempt to deploy an unsigned container image into zt-apps.
# Expected: Kyverno admission webhook rejects the Pod via 'verify-images'.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt01-unsigned-pod.yaml"

REGISTRY_URL="${REGISTRY_URL:-europe-west1-docker.pkg.dev/security-supply-chain/zero-trust}"
RT01_IMAGE="${RT01_IMAGE:-${REGISTRY_URL}/zt-fixtures-unsigned@sha256:0000000000000000000000000000000000000000000000000000000000000001}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-01 requires a reachable Kubernetes cluster with Kyverno installed."
  exit 1
fi

echo "==> [RT-01] Attempting to deploy unsigned image: ${RT01_IMAGE}"
OUT="$(sed "s|\${RT01_IMAGE}|${RT01_IMAGE}|g" "${FIXTURE}" | kubectl apply -f - 2>&1)"
RC=$?

echo "${OUT}"

if [[ ${RC} -ne 0 ]] && grep -q "verify-images" <<<"${OUT}"; then
  echo "[PASS] RT-01 blocked by Kyverno policy 'verify-images'."
  exit 0
fi

echo "[FAIL] RT-01 was NOT blocked by 'verify-images'!"
kubectl -n zt-apps delete pod rt01-unsigned-probe --ignore-not-found >/dev/null 2>&1 || true
exit 1
