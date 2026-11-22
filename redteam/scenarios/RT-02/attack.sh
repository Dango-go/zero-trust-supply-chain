#!/usr/bin/env bash
set -uo pipefail

# RT-02: Attempt to deploy an image signed by an unauthorized OIDC identity (e.g., fork or wrong workflow).
# Expected: Kyverno admission webhook rejects the Pod via 'verify-images' (subjectRegExp mismatch).

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt02-wrong-identity-pod.yaml"

REGISTRY_URL="${REGISTRY_URL:-europe-west1-docker.pkg.dev/security-supply-chain/zero-trust}"
RT02_IMAGE="${RT02_IMAGE:-${REGISTRY_URL}/zt-fixtures-other-identity@sha256:0000000000000000000000000000000000000000000000000000000000000002}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-02 requires a reachable Kubernetes cluster with Kyverno installed."
  exit 1
fi

echo "==> [RT-02] Attempting to deploy image signed by untrusted identity: ${RT02_IMAGE}"
OUT="$(sed "s|\${RT02_IMAGE}|${RT02_IMAGE}|g" "${FIXTURE}" | kubectl apply -f - 2>&1)"
RC=$?

echo "${OUT}"

if [[ ${RC} -ne 0 ]] && grep -q "verify-images" <<<"${OUT}"; then
  echo "[PASS] RT-02 blocked by Kyverno policy 'verify-images'."
  exit 0
fi

echo "[FAIL] RT-02 was NOT blocked by 'verify-images'!"
kubectl -n zt-apps delete pod rt02-wrong-identity-probe --ignore-not-found >/dev/null 2>&1 || true
exit 1
