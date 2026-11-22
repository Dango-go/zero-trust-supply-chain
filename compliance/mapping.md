# Матриця відповідності контролів стандартам (Compliance Mapping)

Цей документ пов'язує технічні контролі платформи **Zero-Trust Supply Chain** із вимогами галузевих стандартів безпеки та артефактами перевірки (policy, workflow, red-team, evidence).

## 1. Зведена таблиця відповідності

| Контроль | SLSA v1.0 | NIST SSDF (SP 800-218) | NIST SP 800-190 | CIS Kubernetes Benchmark | Реалізація в репозиторії | Перевірка / Evidence |
|---|---|---|---|---|---|---|
| Захист гілки `main` та тегів `v*`, `CODEOWNERS`, перевірка дрифту | Source: поза скоупом (задокументовано) | PS.1 | n/a | n/a | [repo-baseline.json](../security/repo-baseline.json), [repo.rego](conftest/repo.rego), [policy-drift.sh](../scripts/policy-drift.sh) | `nightly.yml` (`repo-drift`), `RT-12` |
| Захист CI workflows (`permissions: {}`, pinned SHA, `zizmor`, `actionlint`, `harden-runner`) | Build L3 (ізольований builder) | PO.3, PS.3 | §4.1, §4.2 | n/a | [pr.yml](../.github/workflows/pr.yml), [_build-push.yml](../.github/workflows/_build-push.yml) | `pr.yml` (`security-audit`), `RT-13`, `RT-14` |
| Ізольований SLSA Build L3 Provenance | Build L3 | PS.3, PW.6 | §4.1, §4.2 | n/a | [release.yml](../.github/workflows/release.yml) (`generator_container_slsa3.yml`) | [verify.sh](../scripts/verify.sh), [01-verify-images.yaml](../platform/kyverno/policies/01-verify-images.yaml) |
| Keyless підпис образів (Cosign / Fulcio / Rekor) та деплой за digest | Build L3 (вериф. артефакту) | PS.2 | §4.1, §4.2 | n/a | [_build-sign.yml](../.github/workflows/_build-sign.yml), [02-disallow-latest-tag.yaml](../platform/kyverno/policies/02-disallow-latest-tag.yaml) | `RT-01`, `RT-02`, `RT-03`, `scripts/verify.sh` |
| Генерація та атестація SBOM (CycloneDX) | n/a | PS.3, PW.4 | §4.1 | n/a | [_sbom.yml](../.github/workflows/_sbom.yml), [_build-sign.yml](../.github/workflows/_build-sign.yml) | `RT-05`, [01-verify-images.yaml](../platform/kyverno/policies/01-verify-images.yaml) |
| Scan gate (Trivy + Grype), VEX, `trivyignore` з TTL, нічний rescan | n/a | PW.7, RV.1 | §4.1 | n/a | [_scan-gate.yml](../.github/workflows/_scan-gate.yml), [trivyignore.yaml](../security/trivyignore.yaml), [vex/](../security/vex/), [nightly.yml](../.github/workflows/nightly.yml) | `RT-04`, `RT-05`, [03-deny-revoked-digests.yaml](../platform/kyverno/policies/03-deny-revoked-digests.yaml) |
| Admission hardening: Pod Security `restricted`, реєстри, ресурси, лейбли | n/a | PW.9 | §4.4 | §5.2 | [04-pod-security-restricted.yaml](../platform/kyverno/policies/04-pod-security-restricted.yaml), [06-restrict-registries.yaml](../platform/kyverno/policies/06-restrict-registries.yaml), [07-require-resources.yaml](../platform/kyverno/policies/07-require-resources.yaml), [k8s.rego](conftest/k8s.rego) | `kyverno test`, `conftest test`, `RT-06`, `RT-07` |
| Мережева ізоляція: default-deny, DNS, `toFQDNs`, L7 ingress, Hubble | n/a | n/a | §4.3 | §5.3 | [05-generate-networkpolicy.yaml](../platform/kyverno/policies/05-generate-networkpolicy.yaml), [platform/cilium/](../platform/cilium/) | `RT-08`, `RT-09`, `hubble observe` |
| Динамічні секрети БД, PKI та аудит секретів | n/a | PO.5 | §4.3 | §5.4 | [platform/vault/](../platform/vault/), [platform/vso/](../platform/vso/), [setup-vault.sh](../scripts/setup-vault.sh), [secrets-inventory.md](../docs/secrets-inventory.md) | `gitleaks`, `RT-11` |
| Runtime-детекція загроз (Falco modern eBPF) | n/a | RV.1 | §4.4 | n/a | [platform/falco/](../platform/falco/) | `RT-10`, Falco / Slack logs |
| Безперервний аудит вузлів і кластера | n/a | RV.1 | §4.5 | Усі розділи (node, policies) | [kube-bench/job.yaml](kube-bench/job.yaml), [kubescape/nsa-scan.yaml](kubescape/nsa-scan.yaml), [gen-evidence.sh](../scripts/gen-evidence.sh) | `make compliance` → `docs/evidence/compliance/<date>/` |

---

## 2. Збір доказів (Evidence)

Для генерації актуальних артефактів комплаєнсу використовується команда:

```bash
make compliance
```

Скрипт [gen-evidence.sh](../scripts/gen-evidence.sh) формує каталог `docs/evidence/compliance/<YYYY-MM-DD>/` із результатами:
- `conftest-k8s.json` — перевірка маніфестів політиками Rego;
- `gitleaks.json` — перевірка історії репозиторію на витоки секретів;
- `kube-bench.json` — звіт CIS Kubernetes Benchmark;
- `kubescape.json` — звіт за фреймворками NSA-CISA та MITRE ATT&CK;
- `policyreports.json` / `clusterpolicyreports.json` — поточний стан дотримання політик Kyverno у кластері.

---

## 3. Свідомі обмеження (Scope Boundaries)

- **SLSA Source Track:** формально не заявляється (використовується захист гілок, PR-рев'ю та `policy-drift.sh`, але без атестацій source-track).
- **Публічний Sigstore:** використовуються публічні Fulcio та Rekor; приватний Sigstore не розгортається.
- **PCI-DSS:** використовується як архітектурний контекст для платіжного демо-застосунку, без претензії на формальну сертифікацію.
