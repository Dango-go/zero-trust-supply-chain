# Zero-Trust Software Supply Chain: Threat Model (v2)

This document formalizes the threat landscape, trust boundaries, and compensating controls implemented in the platform.

## Trust Boundaries

```text
[Developer Workstation]
       │ (1) Code / Commits / PR
       ▼
[GitHub Repository & Actions] ──── (6) Third-party Actions / Scanners
       │ (2) OIDC Token / Digest
       ▼
[Sigstore (Fulcio/Rekor) & GHCR]
       │ (3) Image Pull / Verify
       ▼
[Kubernetes Cluster (Admission)]
       │ (4) Network Isolation (Cilium)
       ├──────────────────────────────┐
       ▼                              ▼
  [App Pod A] ── (5) Dynamic DB ──▶ [Vault / PostgreSQL]
       │ (9) Runtime eBPF (Falco)
       ▼
[Attacker / Host OS / Lateral Movement]
```

---

## Threat Matrix & Compensating Controls

| Threat ID | Threat Description | Attack Vector / Real-World Incident | Mitigating Control | Layer | Red-Team Scenario |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T1** | Unauthorized Code Mutation | Direct push to main, compromised contributor account | Branch protection, Rulesets, CODEOWNERS, Signed commits (SSH/Gitsign), 2FA | Source | **RT-12** |
| **T2** | Build Environment / Workflow Compromise | Script injection via `${{ github.event.* }}`, malicious PR code execution | Pinned actions by full SHA, `permissions: {}`, zizmor, actionlint, StepSecurity harden-runner | Build | **RT-13** |
| **T3** | Artifact Tampering in Registry | Tag overwriting (`:latest` mutation), rogue image push | Push by digest, deploy by digest only, Sigstore keyless signing, Rekor log, Kyverno `verifyImages` | Registry / Admission | **RT-01, RT-03** |
| **T4** | Vulnerable Dependencies | Image deployed with known CRITICAL CVE | Pinned hashes, SBOM generation (Syft CycloneDX), Trivy gate, Grype cross-check, signed vuln attestation | Gate / Admission | **RT-05** |
| **T5** | Malicious Dependency Ingestion | Typosquatting, compromised npm/pip package | `--require-hashes` via `uv`/`pip-compile`, Renovate with `minimumReleaseAge: "7 days"`, SBOM audit | Source / Gate | Process / Audit |
| **T6** | Secret Leakage | Static DB passwords in repo or long-lived cloud keys | Gitleaks in CI, Vault Database Engine (dynamic credentials with short TTL), Vault PKI, zero static secrets | Secrets | **RT-11** |
| **T7** | Privileged Workload / Container Escape | Root container, `privileged: true`, hostPath mounts | Pod Security Standards (Restricted) + Kyverno validate policy | Admission | **RT-06** |
| **T8** | Lateral Movement & Exfiltration | Compromised pod scanning cluster network or exfiltrating data | Cilium Default-Deny Ingress/Egress, FQDN egress allowlist, L7 HTTP ingress rules | Network | **RT-08, RT-09** |
| **T9** | Active Runtime Compromise | Interactive shell spawned in container, `/etc/shadow` tampering | Falco eBPF detection rules with real-time alerting via Falcosidekick | Runtime | **RT-10** |
| **T10** | Infrastructure & Compliance Drift | Misconfigured Kubernetes node, weakened admission policies | kube-bench (CIS), Kubescape, Conftest, nightly compliance scans | Compliance | Nightly CI |
| **T11** | **Compromised Security Tool in CI** | Malicious scanner/action stealing OIDC tokens (Trivy incident, March 2026) | Pin actions by digest/SHA, run scan job with zero secrets/no `id-token`, egress allowlist via harden-runner | Build / Gate | **RT-14** |
| **T12** | **Replay of Stale Signed Image** | Validly signed image containing newly discovered CRITICAL CVE is redeployed | Scan freshness condition in Kyverno (≤ 72h), `revoked-digests` ConfigMap, nightly rescan | Admission | **RT-04** |
| **T13** | Unauthorized Release Signing | Attacker pushes `v*` tag to trigger signing workflow | Tag rulesets restricted to maintainers, GitHub Environment `release` with mandatory manual reviewers | Source / Build | **RT-12** |
| **T14** | Trusted Infrastructure Outage | Sigstore Rekor/Fulcio or Kyverno webhook failure | Kyverno HA (3 replicas), Fail-closed policy, audited break-glass `PolicyException` with TTL | Admission | Resilience Runbook |
