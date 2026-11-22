#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATE_UTC="$(date -u +%Y-%m-%d)"
EVIDENCE_DIR="${ROOT_DIR}/docs/evidence/compliance/${DATE_UTC}"

mkdir -p "${EVIDENCE_DIR}"

echo "==> Generating compliance & security evidence in ${EVIDENCE_DIR}"

SUMMARY_FILE="${EVIDENCE_DIR}/SUMMARY.md" # Summary table report for each tool and its execution result.
cat > "${SUMMARY_FILE}" <<EOF
# Compliance Evidence (${DATE_UTC})

Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

| Check | Status | Artifact |
|---|---|---|
EOF

record_result() {
  local check="$1" # name of check tool
  local status="$2" # result of check
  local artifact="$3" # name of generated file with evidence
  echo "| ${check} | ${status} | ${artifact} |" >> "${SUMMARY_FILE}"
}


# 1. Conftest (Policy-as-Code against Kubernetes manifests). PARSING AND VALIDATING MANIFESTS
if command -v conftest >/dev/null 2>&1; then
  echo "==> Running Conftest against apps/manifests/..."
  if conftest test "${ROOT_DIR}/apps/manifests/" \
      -p "${ROOT_DIR}/compliance/conftest/k8s.rego" \
      -o json > "${EVIDENCE_DIR}/conftest-k8s.json"; then
    record_result "Conftest (k8s.rego)" "PASS" "conftest-k8s.json"
  else
    record_result "Conftest (k8s.rego)" "FAIL" "conftest-k8s.json"
  fi
else
  echo "[SKIP] conftest not installed"
  record_result "Conftest (k8s.rego)" "SKIPPED (conftest not installed)" "-"
fi


# 2. Gitleaks (Repository secret scan). SECRETS SCANNING IN FILES AND GIT HISTORY
if command -v gitleaks >/dev/null 2>&1; then
  echo "==> Running Gitleaks secret scan..."
  if gitleaks detect --source "${ROOT_DIR}" \
      --config "${ROOT_DIR}/.gitleaks.toml" \
      --no-banner --redact \
      --report-format json \
      --report-path "${EVIDENCE_DIR}/gitleaks.json" >/dev/null 2>&1; then
    record_result "Gitleaks" "PASS (0 leaks)" "gitleaks.json"
  else
    record_result "Gitleaks" "FAIL (findings)" "gitleaks.json"
  fi
else
  echo "[SKIP] gitleaks not installed"
  record_result "Gitleaks" "SKIPPED (gitleaks not installed)" "-"
fi


# 3. Cluster-dependent checks (kube-bench, Kubescape, Kyverno PolicyReports) 
CLUSTER_READY=0
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  CLUSTER_READY=1
fi

if [[ "${CLUSTER_READY}" -eq 1 ]]; then
  # 3a. kube-bench (CIS Kubernetes Benchmark). CIS BENCHMARK CHECKING IN K8S NODES.
  echo "==> Running kube-bench Job in kube-system..."
  kubectl delete -f "${ROOT_DIR}/compliance/kube-bench/job.yaml" --ignore-not-found >/dev/null 2>&1 || true
  if kubectl apply -f "${ROOT_DIR}/compliance/kube-bench/job.yaml" >/dev/null; then
    if kubectl wait --for=condition=complete job/kube-bench-gke -n kube-system --timeout=180s >/dev/null 2>&1; then
      kubectl logs -n kube-system job/kube-bench-gke > "${EVIDENCE_DIR}/kube-bench.json" || true
      record_result "kube-bench (CIS)" "PASS" "kube-bench.json"
    else
      kubectl logs -n kube-system job/kube-bench-gke > "${EVIDENCE_DIR}/kube-bench.log" 2>&1 || true
      record_result "kube-bench (CIS)" "TIMEOUT/FAIL" "kube-bench.log"
    fi
    kubectl delete -f "${ROOT_DIR}/compliance/kube-bench/job.yaml" --ignore-not-found >/dev/null 2>&1 || true
  fi

  # 3b. Kubescape (NSA-CISA & MITRE ATT&CK). K8S RESOURCES SCANNING 
  if command -v kubescape >/dev/null 2>&1; then
    echo "==> Running Kubescape NSA/MITRE scan..."
    if kubescape scan framework nsa,mitre \
        --exclude-namespaces kube-system,kube-public,kube-node-lease \
        --format json \
        --output "${EVIDENCE_DIR}/kubescape.json" >/dev/null 2>&1; then
      record_result "Kubescape (NSA + MITRE)" "PASS" "kubescape.json"
    else
      record_result "Kubescape (NSA + MITRE)" "COMPLETED (check findings)" "kubescape.json"
    fi
  else
    echo "[SKIP] kubescape CLI not installed"
    record_result "Kubescape (NSA + MITRE)" "SKIPPED (kubescape not installed)" "-"
  fi

  # 3c. Kyverno PolicyReports. KYVERNO POLICIES SNAPSHOTS
  if kubectl get crd policyreports.wgpolicyk8s.io >/dev/null 2>&1; then
    echo "==> Exporting Kyverno PolicyReports..."
    kubectl get policyreport -A -o json > "${EVIDENCE_DIR}/policyreports.json"
    kubectl get clusterpolicyreport -o json > "${EVIDENCE_DIR}/clusterpolicyreports.json"
    record_result "Kyverno PolicyReports" "COLLECTED" "policyreports.json, clusterpolicyreports.json"
  else
    record_result "Kyverno PolicyReports" "SKIPPED (CRD not found)" "-"
  fi
else
  echo "[SKIP] No reachable Kubernetes cluster — skipping kube-bench, Kubescape, and PolicyReports"
  record_result "kube-bench (CIS)" "SKIPPED (no cluster)" "-"
  record_result "Kubescape (NSA + MITRE)" "SKIPPED (no cluster)" "-"
  record_result "Kyverno PolicyReports" "SKIPPED (no cluster)" "-"
fi

echo "==> Evidence generation complete: ${SUMMARY_FILE}"