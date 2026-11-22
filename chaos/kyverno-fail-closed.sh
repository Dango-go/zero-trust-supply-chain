#!/usr/bin/env bash
set -euo pipefail

KYVERNO_NS="${KYVERNO_NS:-kyverno}"
KYVERNO_DEPLOY="${KYVERNO_DEPLOY:-kyverno-admission-controller}"
TEST_NS="${TEST_NS:-zt-apps}"
TEST_POD="chaos-kyverno-fail-closed"

ORIG_REPLICAS=$(kubectl -n "$KYVERNO_NS" get deploy "$KYVERNO_DEPLOY" -o jsonpath='{.spec.replicas}')
ORIG_REPLICAS="${ORIG_REPLICAS:-3}"

cleanup() {
  echo "==> Restoring $KYVERNO_DEPLOY to $ORIG_REPLICAS replicas..."
  kubectl -n "$KYVERNO_NS" scale deploy "$KYVERNO_DEPLOY" --replicas="$ORIG_REPLICAS" >/dev/null 2>&1 || true
  kubectl -n "$TEST_NS" delete pod "$TEST_POD" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> [1/4] Scaling $KYVERNO_DEPLOY in $KYVERNO_NS to 0..."
kubectl -n "$KYVERNO_NS" scale deploy "$KYVERNO_DEPLOY" --replicas=0
kubectl -n "$KYVERNO_NS" wait --for=delete pod -l app.kubernetes.io/component=admission-controller --timeout=60s || true

echo "==> [2/4] Attempting to schedule test pod while Kyverno is down (expecting DENY)..."
set +e
OUTPUT=$(kubectl -n "$TEST_NS" run "$TEST_POD" --image=nginx:latest --restart=Never 2>&1)
RC=$?
set -e

if [ "$RC" -eq 0 ]; then
  echo "FAIL: Pod was admitted even though Kyverno is down (fail-open detected)!"
  exit 1
fi

echo "PASS: Admission rejected request while Kyverno is down:"
echo "  $OUTPUT"

echo "==> [3/4] Restoring $KYVERNO_DEPLOY to $ORIG_REPLICAS replicas..."
kubectl -n "$KYVERNO_NS" scale deploy "$KYVERNO_DEPLOY" --replicas="$ORIG_REPLICAS"
kubectl -n "$KYVERNO_NS" rollout status deploy/"$KYVERNO_DEPLOY" --timeout=120s

echo "==> [4/4] Chaos test kyverno-fail-closed PASSED."
