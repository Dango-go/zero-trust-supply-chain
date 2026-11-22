#!/usr/bin/env bash
set -uo pipefail

# RT-10: Runtime Threat Detection via Falco Modern eBPF
# Expected: Running synthetic attack probe in namespace 'redteam' triggers Falco alert within timeout.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
FIXTURE="${ROOT_DIR}/redteam/fixtures/rt10-event-generator-pod.yaml"
FALCO_NS="${FALCO_NS:-falco}"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] RT-10 requires a reachable Kubernetes cluster with Falco installed."
  exit 1
fi

cleanup() {
  kubectl -n redteam delete pod event-generator-rt10 --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

echo "==> [RT-10] Launching Falco synthetic attack probe in namespace 'redteam'..."
kubectl apply -f "${FIXTURE}"
kubectl -n redteam wait --for=condition=Ready pod/event-generator-rt10 --timeout=60s >/dev/null 2>&1 || true

echo "==> [RT-10] Polling Falco DaemonSet logs for detection alert (timeout: 30s)..."
for _ in $(seq 1 15); do
  LOGS="$(kubectl -n "${FALCO_NS}" logs -l app.kubernetes.io/name=falco --since=2m 2>/dev/null || true)"
  if grep -qE "REDTEAM-SIMULATION|event-generator-rt10|ReadSensitiveFileUntrusted" <<<"${LOGS}"; then
    echo "==> Matching Falco alert found:"
    grep -E "REDTEAM-SIMULATION|event-generator-rt10|ReadSensitiveFileUntrusted" <<<"${LOGS}" | tail -n 5
    echo "[PASS] RT-10 runtime attack detected by Falco eBPF."
    exit 0
  fi
  sleep 2
done

echo "[FAIL] RT-10: Falco did not log the expected runtime alert within 30s!"
exit 1
