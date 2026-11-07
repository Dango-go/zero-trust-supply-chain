#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " Zero-Trust Supply Chain: Automated Red-Team Suite (RT-01..14)"
echo "=========================================================="

SCENARIOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scenarios"
PASSED=0
FAILED=0

echo "Discovering attack scenarios in ${SCENARIOS_DIR}..."

for scenario in "${SCENARIOS_DIR}"/RT-*/attack.sh; do
  if [[ -f "${scenario}" ]]; then
    scenario_id="$(basename "$(dirname "${scenario}")")"
    echo "----------------------------------------------------------"
    echo "Running Scenario: ${scenario_id}"
    echo "----------------------------------------------------------"
    if bash "${scenario}"; then
      echo "[PASS] ${scenario_id}: Attack appropriately blocked or detected."
      ((PASSED++))
    else
      echo "[FAIL] ${scenario_id}: Defense control failed or regression observed."
      ((FAILED++))
    fi
  fi
done

echo "=========================================================="
echo " Red-Team Summary: ${PASSED} Passed, ${FAILED} Failed"
echo "=========================================================="

if [[ ${FAILED} -gt 0 ]]; then
  exit 1
fi
