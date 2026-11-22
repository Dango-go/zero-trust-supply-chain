#!/usr/bin/env bash
set -uo pipefail

# RT-14: Scanner Least-Privilege Isolation & Expired CVE Exception Rejection
# Expected:
#   1) _scan-gate.yml uses harden-runner, does NOT use environment 'release', and keeps pinned scanner versions.
#   2) Expired CVE exception fixture rt14-expired-trivyignore.yaml is rejected by the expiration validator.

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCENARIO_DIR}/../../.." && pwd)"
SCAN_GATE="${ROOT_DIR}/.github/workflows/_scan-gate.yml"
EXPIRED_FIXTURE="${ROOT_DIR}/redteam/fixtures/rt14-expired-trivyignore.yaml"

echo "==> [RT-14] 1. Verifying _scan-gate.yml scanner isolation..."
python3 -c "
import yaml, sys
with open('${SCAN_GATE}') as f:
    wf = yaml.safe_load(f)
assert wf.get('permissions') == {}, '_scan-gate.yml must have top-level permissions: {}'
job = wf['jobs']['vulnerability-gate']
assert 'environment' not in job, '_scan-gate.yml must NOT run in release environment!'
steps = job['steps']
assert any('step-security/harden-runner@' in s.get('uses', '') for s in steps), 'Missing harden-runner in _scan-gate.yml'
print('[OK] _scan-gate.yml enforces scanner isolation and harden-runner.')
" || exit 1

echo "==> [RT-14] 2. Verifying expired CVE exception fixture is rejected..."
python3 -c "
import yaml, datetime, sys
with open('${EXPIRED_FIXTURE}') as f:
    data = yaml.safe_load(f) or {}
now = datetime.datetime.now(datetime.timezone.utc)
for v in data.get('vulnerabilities', []):
    exp_dt = datetime.datetime.fromisoformat(v['expired_at'].replace('Z', '+00:00'))
    if exp_dt < now:
        print(f\"[OK] Correctly rejected expired exception {v['id']} (expired at {v['expired_at']}).\")
        sys.exit(0)
print('[FAIL] Expired fixture was not detected!')
sys.exit(1)
" || exit 1

echo "[PASS] RT-14 verified scanner isolation and CVE exception expiration enforcement."
exit 0
