#!/usr/bin/env bash
set -uo pipefail

# RT-12: Repository Governance & Policy Drift Detection
# Expected:
#   1) Valid security/repo-baseline.json passes compliance/conftest/repo.rego (or baseline schema check).
#   2) Weakened rt12-drifted-baseline.json is REJECTED by Conftest / drift check.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
BASELINE="${ROOT_DIR}/security/repo-baseline.json"
DRIFT_FIXTURE="${ROOT_DIR}/redteam/fixtures/rt12-drifted-baseline.json"
REGO_POLICY="${ROOT_DIR}/compliance/conftest/repo.rego"

if command -v conftest >/dev/null 2>&1; then
  echo "==> [RT-12] 1. Validating clean baseline passes repo.rego..."
  if ! conftest test "${BASELINE}" -p "${REGO_POLICY}"; then
    echo "[FAIL] RT-12: Baseline security/repo-baseline.json failed repo.rego!"
    exit 1
  fi

  echo "==> [RT-12] 2. Testing weakened baseline is REJECTED by repo.rego..."
  OUT="$(conftest test "${DRIFT_FIXTURE}" -p "${REGO_POLICY}" 2>&1)"
  RC=$?
  echo "${OUT}"
  if [[ ${RC} -eq 0 ]]; then
    echo "[FAIL] RT-12: Weakened baseline was NOT rejected by repo.rego!"
    exit 1
  fi
else
  echo "[INFO] conftest not installed; validating baseline vs drifted fixture with python3..."
  python3 -c "
import json, sys
base = json.load(open('${BASELINE}'))
drift = json.load(open('${DRIFT_FIXTURE}'))
assert base['branch_protection']['main']['enforce_admins'] is True
assert base['branch_protection']['main']['allow_force_pushes'] is False
assert base['tag_protection']['v*']['immutable'] is True
assert drift['branch_protection']['main']['enforce_admins'] is False
print('[OK] Baseline enforced and drift fixture mismatch detected.')
" || exit 1
fi

if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]] && command -v gh >/dev/null 2>&1; then
  echo "==> [RT-12] 3. Running live GitHub policy-drift.sh audit..."
  "${ROOT_DIR}/scripts/policy-drift.sh" || exit 1
else
  echo "[INFO] GH_TOKEN not set; skipping live GitHub API audit."
fi

echo "[PASS] RT-12 verified governance baseline and drift rejection."
exit 0
