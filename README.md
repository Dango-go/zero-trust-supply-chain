# Zero-Trust Software Supply Chain System

> **Zero-Trust Software Supply Chain Platform (v2)** — наскрізна DevSecOps-система захисту ланцюга постачання ПЗ від коду до Kubernetes-runtime на основі принципу нульової довіри (*chain of custody*).

---

## Preview

*(Буде додано: архітектурна діаграма, демонстрація блокування unsigned/replay образів, Falco-алерти та Hubble-трафік)*

---

## Stack

Повний технологічний стек платформи, розбитий за функціональними рівнями безпеки згідно з [PLAN.md](PLAN.md):

### 1. Source & Repository Security
* **VCS & Governance:** GitHub (Repository Rulesets, Tag Rulesets для `v*`, CODEOWNERS, Environments з обов'язковими reviewers).
* **Commit Integrity:** Git Signed Commits (SSH / Gitsign).
* **SAST & Linting:**
  * **Semgrep** — статичний аналіз коду на вразливості.
  * **Gitleaks** — превентивний та історичний пошук витоку секретів.
  * **Hadolint** — лінтинг та перевірка бест-практик Dockerfile.
  * **Actionlint & Zizmor** — аудит та перевірка безпеки GitHub Actions workflows (захист від template injection, unpinned actions, надлишкових permissions).
* **Policy-as-Code:** **Conftest (OPA / Rego)** — валідація Kubernetes-маніфестів та еталону конфігурації репозиторію (`repo-baseline.json`).
* **Dependency Management:** **Renovate** — автоматичне оновлення залежностей із закріпленням хешів (`helpers:pinGitHubActionDigests`), групуванням патчів та затримкою релізів (`minimumReleaseAge`).

### 2. CI/CD & Build Pipeline
* **CI/CD Orchestration:** **GitHub Actions** (модульні Reusable Workflows, ізольовані ephemeral runners, суворий принцип найменших привілеїв `permissions: {}`).
* **CI Runtime Protection:** **StepSecurity Harden-Runner** — аудит та блокування несанкціонованого мережевого трафіку (egress allowlist) на runner-ах для запобігання ексфільтрації секретів скомпрометованими інструментами.
* **Containerization:** **Docker / Buildx** (multi-stage збірка, push суворо **by digest**, непривілейований `USER` з UID > 10000, підтримка `readOnlyRootFilesystem`).
* **Base Images:** **Chainguard Images / Google Distroless** (мінімалістичні образи без шелів та зайвих пакетів, закріплені за digest із верифікацією підпису upstream).
* **Demo Microservices:** **Python (FastAPI)**, залежності з контролем хешів (`pip-compile --generate-hashes` / `uv`).
* **Provenance Generation:** **SLSA GitHub Generator** (`generator_container_slsa3.yml`) — генерація криптографічно підписаного SLSA Build L3 provenance у ізольованій джобі після scan-gate.

### 3. Supply Chain Security & Artifact Integrity
* **Cryptographic Signing & Verification:** **Sigstore Stack** (Keyless підпис на базі ефемерних OIDC X.509 сертифікатів):
  * **Cosign** — підпис образів за digest, прикріплення та верифікація атестацій.
  * **Fulcio** — CA, що випускає короткоживучі сертифікати на основі GitHub Actions OIDC токенів.
  * **Rekor** — незмінний публічний журнал прозорості (transparency log).
* **Artifact Registry:** **GitHub Container Registry (GHCR)** — зберігання OCI-образів, підписів та атестацій за digest.
* **SBOM (Software Bill of Materials):** **Syft (Anchore)** — генерація специфікацій компонентів у форматі **CycloneDX JSON**.
* **Vulnerability Scanning & VEX:**
  * **Trivy (Aqua Security)** — сканування вразливостей (запуск із закріпленого digest, без секретів, генерація звіту у форматі `cosign-vuln`).
  * **Grype (Anchore)** — вторинне незалежне сканування ("друга думка").
  * **OpenVEX** / `.trivyignore.yaml` — декларування винятків із обов'язковим терміном дії (`expired_at`).

### 4. Admission Control & Cluster Security
* **Container Orchestration:** **Kubernetes (kind)** — 1 Control-Plane + 2 Workers, `disableDefaultCNI: true`.
* **Policy Engine / Admission Controller:** **Kyverno HA** (3 репліки, fail-closed `failurePolicy: Fail`):
  * `verifyImages` — верифікація підпису, SBOM, результатів сканування (0 CRITICAL, свіжість ≤ 72h) та SLSA provenance із JMESPath `conditions`.
  * `deny-revoked-digests` — оперативне блокування скомпрометованих або відкликаних digest-ів через ConfigMap.
  * `pod-security-restricted` — enforce стандарту Pod Security Standards (PSS) Restricted.
  * `disallow-latest-tag`, `restrict-registries`, `require-resources`, `generate-networkpolicy`.
* **Break-Glass:** Контрольовані винятки через `PolicyException` із прив'язкою до namespace, анотацією аудиту та обмеженим TTL.

### 5. Network Security & Observability
* **CNI & eBPF Datapath:** **Cilium** (eBPF kernel-level мережева фільтрація без iptables):
  * **Default-Deny:** автоматичне блокування всього Ingress/Egress трафіку за замовчуванням.
  * **Egress Control:** L3/L4 фільтрація за доменними іменами через `toFQDNs` із захищеним Cilium DNS-проксі.
  * **L7 Ingress Policies:** фільтрація методів та шляхів внутрішнього HTTP-трафіку (наприклад, дозволено лише `POST /v1/charge`).
* **Node-to-Node Encryption:** **WireGuard** (прозоре шифрування pod-to-pod трафіку без втрати L7-видимості для Cilium).
* **Network Observability:** **Hubble (Relay + UI)** — візуалізація та аудит мережевих потоків, дропів та DNS-запитів у реальному часі.

### 6. Secrets Management & PKI
* **Secrets Engine:** **HashiCorp Vault HA** (кластер із 3 pod-ів з Integrated Storage / Raft):
  * **Vault Database Engine** — генерація динамічних короткоживучих облікових даних (PostgreSQL) із автоматичною ротацією (TTL 1h / max 24h).
  * **Vault PKI Secrets Engine** — внутрішній удостовіряючий центр (CA) для випуску короткоживучих TLS-сертифікатів.
* **Secret Delivery:** **Vault Secrets Operator (VSO)** — автоматична доставка динамічних секретів у Kubernetes та trigger rollout restarts при ротації.
* **Certificate Lifecycle:** **cert-manager** з інтеграцією Vault Issuer (`sslmode=verify-full`).
* **Database:** **PostgreSQL** — база даних із підтримкою динамічних ролей та обов'язковим TLS-з'єднанням.

### 7. Runtime Security & Detection
* **Threat Detection:** **Falco** (з сучасним eBPF driver) — моніторинг системних викликів ядра, виявлення підозрілої активності (інтерактивні шели в контейнерах, модифікація `/etc`, читання `/etc/shadow`).
* **Alert Routing:** **Falcosidekick** — агрегація та доставка сповіщень безпеки в канали сповіщень (Slack / Grafana Loki).
* **Runtime Enforcement (Stretch/Optional):** **Tetragon** — запобіжне блокування загроз на рівні ядра (eBPF enforcement / SIGKILL).

### 8. Continuous Security, Audit & Red-Teaming
* **Continuous Rescan:** **Trivy Operator** / Nightly CronJob — моніторинг працюючих digest-ів на нові CVE та автоматичний GitOps PR у `revoked-digests.yaml`.
* **Security & Compliance Auditing:**
  * **kube-bench** — перевірка відповідності кластера CIS Kubernetes Benchmark.
  * **Kubescape** — аудит на відповідність стандартам NSA-CISA та матриці MITRE ATT&CK.
  * **OpenSSF Scorecard** — публічна оцінка здоров'я та безпеки репозиторію.
* **Automated Red-Teaming (14 Scenarios):** Набір сценаріїв **RT-01...RT-14** (Bash, Kind, Cosign, Hubble, Falco) із генерацією JUnit-звітів та evidence-артефактів для доведення надійності кожного шару захисту.


---

## CI/CD Pipeline Architecture

The platform enforces a strict separation of privileges using two distinct GitHub Actions workflows:

### 1. `pr.yml` (Pre-Merge Validation)
* **Trigger:** Automatically triggered upon creating or updating a Pull Request targeting the `main` branch.
* **Purpose:** Rapid-feedback quality and security validation — runs workload unit tests, code linters, secret leak detection (`Gitleaks`), Dockerfile linting (`Hadolint`), and workflow security static analysis (`Actionlint`, `Zizmor`).
* **Security Boundary:** Runs under a strict least-privilege model (`permissions: {}`). Access to OIDC tokens, artifact signing capabilities, and registry write credentials is **strictly forbidden**.
  Особливості пайплайну:
  В обох джобах використано на початку утиліту Harden runner для відстеження безпечного завантаження через мережу залежностей в режимі audit.



### 2. `release.yml` (Official Release Orchestrator)
* **Trigger:** Triggered exclusively when an authorized maintainer pushes a semantic version tag (e.g., `git tag v1.0.0 && git push origin v1.0.0`).
* **Purpose:** Orchestrates the multi-stage build, scan, provenance, and signing process. Builds container images pushed strictly **by digest**, generates CycloneDX SBOMs, enforces vulnerability gates (`Trivy` + `Grype`), generates SLSA Build L3 provenance, and attaches cryptographic signatures to GHCR.
* **Security Boundary:** Keyless signing credentials (`id-token: write`) are strictly confined to the final signing job operating within a protected GitHub **`release` Environment**, requiring mandatory human review and approval.
  Особливості пайплайну:
  1. Спрацьовує в разі пушу коміту з версією v*. Для цього необхідно спочатку у налаштуваннях GitHub (розділ Rulesets) налаштувати правило для тегів.
  2. Захист прямо в коді пайплайну (перевірка git merge-base)

Образ після збірки сканується до підпису. Підпис ставиться тільки на перевірений результат.


Застосування додатку в кластері:
Перш ніж Kubernetes взагалі дозволить створити Pod або потягнути образ із Google Artifact Registry, запит перехоплює Kyverno.
Kyverno йде в Sigstore (Rekor) і Google Artifact Registry і робить 3 незалежні перевірки:
  1. Підпис (Signature)
  2. Зміст атестацій (SBOM + Scan)
  3. Доказ походження (SLSA Provenance)

Якщо підписи ідеальні, Kyverno та Kubernetes перевіряють сам маніфест:
  Non-root, readOnlyRootFilesystem: true, capabilities (drop: [ALL]).

Якщо етапи вище пройдені, образ завантажується на ноду в кластер:
  1. Мережева ізоляція (Cilium eBPF): На под вішається Default-Deny.
  2. Секрети (Vault Secrets Operator — VSO): VSO звертається до HashiCorp Vault ➔ Vault на льоту створює в PostgreSQL нового користувача з паролем на 1 годину (TTL) ➔ передає в контейнер.
  3. Runtime-нагляд (Falco eBPF): Falco стежить за системними викликами ядра.

ІНСТРУМЕНТИ КЛАСТЕРА:
  1. Trivy Operator
  2. kube-bench (CIS Kubernetes Benchmark)
  3. Kubescape
  4. Tetragon
  5. WireGuard
  6. Sigstore (Fulcio + Rekor)
  7. Cilium eBPF
  8. Hubble (Relay + UI)
  9. Falco
  10. Kyverno HA
  11. HashiCorp Vault HA (Raft)
  12. Vault Secrets Operator (VSO)
  13. cert-manager
  14. Falcosidekick
  15. PostgreSQL
  

Додаткові зовнішні сервіси: Google Cloud KMS


**Kyverno**
Preview:
В саму архітекутуру не включаємо в проєкт kyverno/kyverno-policies. Власні політики в platform/kyverno/policies/.
Опціонально підключаємо kyverno/policy-reporter окремим чартом для UI-інтеграції.

Role in project:
