#!/usr/bin/env bash
set -uo pipefail

# RT-07: Attempt to deploy an image from an untrusted public registry (docker.io).
# Expected: Kyverno admission webhook rejects the Pod via 'restrict-registries'.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt07-untrusted-registry-pod.yaml"

RT07_IMAGE="${RT07_IMAGE:-docker.io/library/nginx@sha256:0000000000000000000000000000000000000000000000000000000000000007}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-07 requires a reachable Kubernetes cluster with Kyverno installed."
  exit 1
fi

echo "==> [RT-07] Attempting to deploy image from untrusted registry: ${RT07_IMAGE}"
OUT="$(sed "s|\${RT07_IMAGE}|${RT07_IMAGE}|g" "${FIXTURE}" | kubectl apply -f - 2>&1)"
RC=$?

echo "${OUT}"

if [[ ${RC} -ne 0 ]] && grep -q "restrict-registries" <<<"${OUT}"; then
  echo "[PASS] RT-07 blocked by Kyverno policy 'restrict-registries'."
  exit 0
fi

echo "[FAIL] RT-07 was NOT blocked by 'restrict-registries'!"
kubectl -n zt-apps delete pod rt07-untrusted-registry-probe --ignore-not-found >/dev/null 2>&1 || true
exit 1
