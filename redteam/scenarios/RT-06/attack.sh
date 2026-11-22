#!/usr/bin/env bash
set -uo pipefail

# RT-06: Attempt to deploy a privileged Pod (root, hostNetwork, hostPath, privileged: true).
# Expected: Blocked by Pod Security Admission (restricted) and/or Kyverno 'pod-security-restricted'.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt06-privileged-pod.yaml"

REGISTRY_URL="${REGISTRY_URL:-europe-west1-docker.pkg.dev/security-supply-chain/zero-trust}"
RT06_IMAGE="${RT06_IMAGE:-${REGISTRY_URL}/zt-orders@sha256:0000000000000000000000000000000000000000000000000000000000000006}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-06 requires a reachable Kubernetes cluster."
  exit 1
fi

echo "==> [RT-06] Attempting to deploy privileged/hostPath/root Pod..."
OUT="$(sed "s|\${RT06_IMAGE}|${RT06_IMAGE}|g" "${FIXTURE}" | kubectl apply -f - 2>&1)"
RC=$?

echo "${OUT}"

if [[ ${RC} -ne 0 ]] && grep -qE "pod-security-restricted|violates PodSecurity" <<<"${OUT}"; then
  echo "[PASS] RT-06 blocked by PSA restricted / Kyverno 'pod-security-restricted'."
  exit 0
fi

echo "[FAIL] RT-06 was NOT blocked by PSA or 'pod-security-restricted'!"
kubectl -n zt-apps delete pod rt06-privileged-probe --ignore-not-found >/dev/null 2>&1 || true
exit 1
