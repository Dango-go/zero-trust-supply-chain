#!/usr/bin/env bash
set -uo pipefail

# RT-13: Vulnerable CI Workflow & Script Injection Detection
# Expected:
#   1) All production workflows in .github/workflows/ declare top-level 'permissions: {}' and avoid 'write-all'.
#   2) Vulnerable fixture rt13-vulnerable-workflow.yml is caught by zizmor (or static security audit).

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
VULN_FIXTURE="${ROOT_DIR}/redteam/fixtures/rt13-vulnerable-workflow.yml"

echo "==> [RT-13] 1. Verifying production workflows enforce 'permissions: {}' and no dangerous triggers..."
python3 -c "
import glob, yaml, sys
for path in sorted(glob.glob('${ROOT_DIR}/.github/workflows/*.yml')):
    with open(path) as f:
        wf = yaml.safe_load(f)
    if wf.get('permissions') != {}:
        print(f'[FAIL] {path} must define top-level permissions: {{}}, got {wf.get(\"permissions\")}')
        sys.exit(1)
    on_block = wf.get(True, wf.get('on', {}))
    if isinstance(on_block, dict) and 'pull_request_target' in on_block:
        print(f'[FAIL] {path} uses dangerous pull_request_target trigger!')
        sys.exit(1)
print('[OK] All production workflows enforce top-level permissions: {} and safe triggers.')
" || exit 1

echo "==> [RT-13] 2. Auditing vulnerable workflow fixture with zizmor / static check..."
if command -v zizmor >/dev/null 2>&1; then
  OUT="$(zizmor "${VULN_FIXTURE}" 2>&1)"
  RC=$?
  echo "${OUT}"
  if [[ ${RC} -eq 0 ]]; then
    echo "[FAIL] RT-13: zizmor did NOT catch vulnerable workflow fixture!"
    exit 1
  fi
else
  echo "[INFO] zizmor not installed locally; running static workflow policy check against fixture..."
  if grep -qE "write-all|pull_request_target|\$\{\{ github\.event\." "${VULN_FIXTURE}"; then
    echo "[OK] Caught dangerous patterns (write-all / pull_request_target / template injection) in fixture."
  else
    echo "[FAIL] RT-13: Expected vulnerable patterns not flagged!"
    exit 1
  fi
fi

echo "[PASS] RT-13 verified CI workflow hardening and vulnerable workflow detection."
exit 0
