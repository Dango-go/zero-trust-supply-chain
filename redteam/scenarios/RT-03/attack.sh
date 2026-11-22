#!/usr/bin/env bash
set -uo pipefail

# RT-03: Attempt to deploy a pod using a mutable ':latest' tag instead of an immutable @sha256 digest.
# Expected: Kyverno admission webhook rejects the Pod via 'disallow-latest-tag'.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt03-latest-tag-pod.yaml"

REGISTRY_URL="${REGISTRY_URL:-europe-west1-docker.pkg.dev/security-supply-chain/zero-trust}"
RT03_IMAGE="${RT03_IMAGE:-${REGISTRY_URL}/zt-orders:latest}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-03 requires a reachable Kubernetes cluster with Kyverno installed."
  exit 1
fi

echo "==> [RT-03] Attempting to deploy mutable ':latest' tag: ${RT03_IMAGE}"
OUT="$(sed "s|\${RT03_IMAGE}|${RT03_IMAGE}|g" "${FIXTURE}" | kubectl apply -f - 2>&1)"
RC=$?

echo "${OUT}"

if [[ ${RC} -ne 0 ]] && grep -q "disallow-latest-tag" <<<"${OUT}"; then
  echo "[PASS] RT-03 blocked by Kyverno policy 'disallow-latest-tag'."
  exit 0
fi

echo "[FAIL] RT-03 was NOT blocked by 'disallow-latest-tag'!"
kubectl -n zt-apps delete pod rt03-latest-tag-probe --ignore-not-found >/dev/null 2>&1 || true
exit 1
