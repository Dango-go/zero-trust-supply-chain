#!/usr/bin/env bash
set -uo pipefail

# RT-05: Deploy a signed image that lacks required SBOM/SLSA provenance attestations
#        or contains CRITICAL CVEs in its vulnerability attestation.
# Expected: Kyverno admission webhook rejects the Pod via 'verify-images'.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt05-missing-attestations-pod.yaml"

REGISTRY_URL="${REGISTRY_URL:-europe-west1-docker.pkg.dev/security-supply-chain/zero-trust}"
RT05_IMAGE="${RT05_IMAGE:-${REGISTRY_URL}/zt-fixtures-no-attestations@sha256:0000000000000000000000000000000000000000000000000000000000000005}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-05 requires a reachable Kubernetes cluster with Kyverno installed."
  exit 1
fi

echo "==> [RT-05] Attempting to deploy image without valid attestations / with CRITICAL CVE: ${RT05_IMAGE}"
OUT="$(sed "s|\${RT05_IMAGE}|${RT05_IMAGE}|g" "${FIXTURE}" | kubectl apply -f - 2>&1)"
RC=$?

echo "${OUT}"

if [[ ${RC} -ne 0 ]] && grep -q "verify-images" <<<"${OUT}"; then
  echo "[PASS] RT-05 blocked by Kyverno policy 'verify-images'."
  exit 0
fi

echo "[FAIL] RT-05 was NOT blocked by 'verify-images'!"
kubectl -n zt-apps delete pod rt05-missing-attestations-probe --ignore-not-found >/dev/null 2>&1 || true
exit 1
