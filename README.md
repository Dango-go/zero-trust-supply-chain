# Zero-Trust Software Supply Chain System

> **Zero-Trust Software Supply Chain Platform (v2)** — An end-to-end DevSecOps system for securing the software supply chain—from code to Kubernetes runtime—based on the Zero Trust principle (*chain of custody*).

---

## Preview

*(Буде додано: архітектурна діаграма, демонстрація блокування unsigned/replay образів, Falco-алерти та Hubble-трафік)*

---

## Technology Stack

The platform is designed around strict trust boundaries and defense-in-depth across eight operational security layers:

| Security Layer | Operational Domain | Key Technologies & Implementations |
| :--- | :--- | :--- |
| **1. Cloud & Identity (IaC)** | Infrastructure & IAM | **Google Cloud Platform (GCP)**: Hardened Private GKE (Datapath v2 / Cilium eBPF), Shielded Nodes, Workload Identity Federation (WIF), Google Artifact Registry (GAR), Google Cloud KMS, Terraform |
| **2. Source & Policy-as-Code** | Governance & Shift-Left | GitHub Enterprise (Repository Rulesets, Tag Rulesets for `v*`, CODEOWNERS), Commit Signing (Gitsign / SSH), **Conftest (OPA / Rego)**, **Checkov**, **Gitleaks**, **Hadolint**, **actionlint**, **zizmor**, Renovate |
| **3. Build & CI Pipeline** | Hardened Orchestration | **GitHub Actions** (isolated reusable workflows, least-privilege `permissions: {}`), **StepSecurity Harden-Runner** (egress audit & blocking), Docker Buildx (multi-stage non-root, push-by-digest), Python FastAPI microservices (`uv`, hash-pinned deps) |
| **4. Supply Chain & Integrity** | Signatures & Provenance | **Sigstore Stack** (Cosign Keyless, Fulcio CA, Rekor Transparency Log), **Syft** (CycloneDX JSON SBOM), **SLSA Build L3 Generator** (`generator_container_slsa3.yml`), **Trivy** (Aqua Security, 0 CRITICAL gate), **Grype**, OpenVEX / `.trivyignore.yaml` |
| **5. Admission Control** | Fail-Closed Policy Enforcement | **Kyverno HA** (3 replicas, `failurePolicy: Fail`, 5 ClusterPolicies: `verifyImages`, `disallow-latest-tag`, `deny-revoked-digests`, `pod-security-restricted`, `generate-networkpolicy`), PolicyExceptions (time-bounded break-glass) |
| **6. Network Security** | eBPF Zero-Trust Perimeter | **Cilium (GKE Datapath v2)**: Default-Deny Ingress/Egress, L7 HTTP Filtering (`POST /v1/charge`), FQDN Outbound Whitelisting (`toFQDNs`), DNS Proxy with FQDN inspection, WireGuard pod-to-pod encryption, **Hubble** (Relay + UI) |
| **7. Secrets Management & PKI** | Dynamic Credentials & DB | **HashiCorp Vault HA** (3 replicas, Integrated Raft Storage, Cloud KMS Auto-Unseal, Database Secrets Engine with 1h TTL dynamic credentials), **Vault Secrets Operator (VSO)**, **cert-manager** (automated webhook PKI & internal TLS), **CloudNativePG** (PostgreSQL 16 HA) |
| **8. Runtime & Compliance** | Threat Detection & Evidence | **Falco** (Modern eBPF driver, unprivileged capabilities: `BPF`, `PERFMON`), **Falcosidekick**, **Grafana Loki** (audit-trail), **kube-bench** (CIS K8s Benchmark), **Kubescape** (NSA-CISA / MITRE ATT&CK), OpenSSF Scorecard, Automated Red-Team Suite (RT-01..RT-14) |

---

### Application Architecture & Endpoints

Платформа розгортає демонстраційну мікросервісну архітектуру з двох сервісів на базі **FastAPI**, яка моделює типовий PCI-DSS платіжний контур:

```
[ Клієнт ] ───▶ POST /orders ───▶ [ zt-orders ] ───(HTTP POST /v1/charge)───▶ [ zt-payments ] ───▶ [ External PSP ]
                                        │                                                             (FQDN / 443)
                                        ▼ (asyncpg)
                               [ PostgreSQL (CNPG) ]
                                (Таблиця: orders)
```

#### 1. Сервіс замовлень (`zt-orders`)
Центральний бізнес-сервіс, відповідальний за створення, збереження та перегляд замовлень. Єдиний сервіс, що має доступ до бази даних.

* **Ендпоінти сервісу:**
  * **`GET /healthz` (Liveness Probe):** Перевіряє працездатність процесу додатка (повертає `{"status": "ok"}`).
  * **`GET /readyz` (Readiness Probe):** Перевіряє активність підключення до PostgreSQL через динамічні креденшіали Vault. Якщо база недоступна або пароль у процесі ротації — повертає `503 Service Unavailable`.
  * **`POST /orders` (Створення замовлення):**
    * **Вхідне тіло (JSON):** `{"item": "string", "quantity": int, "amount": float, "currency": "USD"}`.
    * **Флоу та логіка обробки:**
      1. Генерує унікальний `order_id` (наприклад, `ord_a1b2c3d4e5f6`).
      2. Робить синхронний виклик до сервісу платежів: `POST http://zt-payments:8080/v1/charge` (цей шлях суворо валідується та дозволяється політикою **Cilium L7**).
      3. Отримує від платіжного сервісу ID транзакції (`tx_id`).
      4. Зберігає замовлення зі статусом `COMPLETED` та отриманим `tx_id` у базу даних PostgreSQL через асинхронний пул `asyncpg`.
    * **Відповідь (201 Created):** Повний об'єкт замовлення з `id`, статусом та `payment_tx_id`.
  * **`GET /orders/{order_id}`:** Отримання деталей конкретного замовлення з бази даних за його ідентифікатором.
  * **`GET /orders`:** Отримання повного списку всіх збережених замовлень.

#### 2. Сервіс платежів (`zt-payments`)
Транзитний платіжний сервіс (без стану / stateless). Не має власної бази даних і не має жодного доступу до PostgreSQL.

* **Ендпоінти сервісу:**
  * **`GET /healthz`:** Перевірка доступності сервісу (дозволена Cilium L7 політикою).
  * **`POST /v1/charge` (Обробка платежу):**
    * **Вхідне тіло (JSON):** `{"order_id": "string", "amount": float, "currency": "USD"}`.
    * **Флоу та логіка обробки:**
      1. Приймає запит виключно від сервісу `zt-orders` (будь-які інші джерела блокуються на рівні мережі).
      2. Емулює проведення банківської транзакції та токенізацію.
      3. Генерує криптографічний ідентифікатор транзакції `tx_id` (наприклад, `tx_9f8e7d6c5b4a3210`).
      4. При потребі надсилає сповіщення на зовнішній платіжний шлюз PSP (вихід контролюється Cilium через FQDN whitelisting на 443 порт).
    * **Відповідь (201 Created):** `{"status": "CHARGED", "tx_id": "string", "order_id": "string", "amount": float, "currency": "USD"}`.


### Схема та структура бази даних PostgreSQL

У базі даних створюється **1 таблиця** під назвою **`orders`** (неймспейс `zt-data`, кластер `CloudNativePG`, база `orders`):

| Поле (Column) | Тип даних (Data Type) | Опис та обмеження |
| :--- | :--- | :--- |
| **`id`** | `VARCHAR(64)` | Первинний ключ (**PRIMARY KEY**), унікальний ідентифікатор замовлення (`ord_...`) |
| **`item`** | `VARCHAR(128)` | Назва замовленого товару або послуги (`NOT NULL`) |
| **`quantity`** | `INTEGER` | Кількість одиниць товару (`NOT NULL`) |
| **`amount`** | `NUMERIC(10, 2)` | Сума замовлення з точністю до копійок (`NOT NULL`) |
| **`currency`** | `VARCHAR(3)` | Трьохсимвольний код валюти за ISO 4217 (за замовчуванням `USD`, `NOT NULL`) |
| **`status`** | `VARCHAR(32)` | Стан обробки замовлення (`COMPLETED`, `FAILED`, `PENDING`) |
| **`payment_tx_id`** | `VARCHAR(64)` | Ідентифікатор транзакції від сервісу платежів (`tx_...`), зв'язує замовлення з оплатою |
| **`created_at`** | `TIMESTAMP WITH TIME ZONE` | Час створення запису (за замовчуванням `CURRENT_TIMESTAMP`) |


### Zero-Trust автентифікація до бази даних (Vault + VSO)

- **`zt-orders`** — єдиний сервіс, що має право доступу до порту 5432 (`postgres-rw` у `zt-data`), що примусово гарантується мережевою політикою Cilium.
- **Динамічні креденшіали (No Static Passwords):**
  1. Оператор **VSO (`VaultSecretsOperator`)** за допомогою `VaultAuth` звертається до HashiCorp Vault за адресою `database/creds/orders-rw`.
  2. Сервер Vault звертається до PostgreSQL і генерує одноразового користувача з терміном дії 1 година (TTL = 1h):
     ```sql
     CREATE ROLE "v-kubernet-orders-rw-1715892341" WITH LOGIN PASSWORD 'A1b2C3d4E5f6G7h8_secure_pass!' VALID UNTIL '...';
     GRANT CONNECT ON DATABASE orders TO "v-kubernet-orders-rw-1715892341";
     GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO "v-kubernet-orders-rw-1715892341";
     ```
  3. VSO створює в Kubernetes Secret `orders-db-creds` із ключами `username` та `password`.
  4. Секрет монтується у контейнер `zt-orders` у віртуальну пам'ять (**RAM-диск `tmpfs`**) у каталог `/vault/secrets/`. Пароль ніколи не пишеться на фізичний диск ноди!
  5. Додаток через `src/config.py` читає креденшіали з пам'яті й підключається через `asyncpg`. Коли 1 година спливає, VSO оновлює секрет, а старий юзер у PostgreSQL автоматично видаляється (`DROP ROLE`).


### Ротація & Аварія
**Етап планової ротації**: VSO не чекає останньої секунди скидання паролю через tTL таймер (бо якби був лаг мережі — додаток упав би). Зазвичай за 10-15% до кінця строку (десь на 50-й хвилині) VSO починає процедуру ротації. VSO шле запит до Vault на створення нового пароля. В цей момент в базі даних створюється два користувачі. Після цього VSO перезаписує значення в Secret orders-db-creds. Оскільки цей секрет змонтовано в под zt-orders, Kubernetes оновлює вміст файлів у пам'яті /vault/secrets/.
  VSO тригерить Rolling Update для Deployment: піднімається новий под zt-orders, зчитує вже новий пароль, встановлює з'єднання з базою, проходить перевірку /readyz, і тільки після цього старий под гаситься. Жоден клієнтський запит не губиться!
  Це відбувається завдяки написаному блоку
  restartTarget:
    kind: Deployment
    name: zt-orders

**Етап планової аварії**: Наприклад через под хтось підключився до бази даних. Falco бачить, що в контейнері запущено невідомий процес або спробу злити пам'ять. Falco передає алерт у систему реакції (Responder).
Система безпеки або людина виконує команду: 
  vault lease revoke -prefix database/creds/orders-rw - Сервер Vault парсить усі активні leases, чий ID починається з database/creds/orders-rw/. Для кожного з них Vault бере заздалегідь налаштовані у scripts/setup-vault.sh SQL-команди (revocation_statements) і виконує їх у PostgreSQL. Після цього Vault видаляє ці лізи зі своєї бази.

  Якщо потрібно повністю автоматизувати процес, можна використати Falco Talon, у який Falcosidekick шле тривогу, а респондер уже смикає API Vault.
  Ця команда виконується локального терміналу через проброс портів, через ексек в поді вольт сервера, через Falco Talon тоді він навіть не викликає CLI, а просто шле той самий HTTP PUT-запит на API Vault.

---

### CI/CD Pipeline Architecture

The platform uses a modular, least-privilege CI/CD architecture built on **GitHub Actions**. Pipelines strictly segregate duties across pull request checks, immutable release workflows, and recurring security audits.

```
                  [ Pull Request to main ]
                             │
                             ▼
                        ┌──────────┐
                        │  pr.yml  │  (SAST, Linters, Checkov, Gitleaks, Hadolint, Unit Tests)
                        └──────────┘

                  [ Release Tag v* on main ]
                             │
                             ▼
                       ┌─────────────┐
                       │ release.yml │  (Release Orchestrator)
                       └──────┬──────┘
                              │
         ┌────────────────────┼────────────────────┬────────────────────┐
         ▼                    ▼                    ▼                    ▼
 ┌───────────────┐    ┌───────────────┐    ┌───────────────┐    ┌───────────────┐
 │_build-push.yml│───▶│   _sbom.yml   │───▶│ _scan-gate.yml│───▶│_build-sign.yml│
 └───────────────┘    └───────────────┘    └───────────────┘    └───────────────┘
   (Buildx to GAR      (Syft CycloneDX      (Trivy CRITICAL=0    (Cosign Keyless
    by Digest)           Validation)          & Grype Double-Check) & Attestations)

                  [ Scheduled Cron (02:00 UTC) ]
                             │
                             ▼
                       ┌─────────────┐
                       │ nightly.yml │  (Rescan CVEs, Drift Check, Scorecard, Red-Team)
                       └─────────────┘
```

---

### Pipeline Workflows Overview

* **`pr.yml` (Pre-Merge Validation Gate)**
  * **Trigger:** Any Pull Request opened, synchronized, or reopened targeting `main`.
  * **Security Profile:** Zero token permissions (`permissions: {}`), completely isolated from cloud infrastructure and signing keys.
  * **Execution:**
    * Hardens the runner environment with step-security `harden-runner` in audit mode.
    * Scans commits and history for leaked secrets, credentials, and API keys via `Gitleaks`.
    * Lints Dockerfiles for security anti-patterns and layer optimization using `Hadolint`.
    * Audits workflow syntax, shell injections, and GitHub Actions misconfigurations with `actionlint` and `Zizmor`.
    * Scans Terraform infrastructure code (`tf/`) for CIS Google Cloud Benchmark violations via `Checkov`.
    * Validates Kubernetes manifests and repository baselines using **`Conftest` (OPA / Rego)** before merge.
    * Ensures active vulnerability exception entries in `.trivyignore.yaml` have not passed their `expired_at` deadline.
    * Executes microservice unit test suites (`zt-orders`, `zt-payments`) with `pytest` and `uv`.
  * **Outcome:** Enforces quality and security gates before merge; failures strictly block PR approval.

* **`release.yml` (Release Orchestrator)**
  * **Trigger:** Push of a semantic version tag (e.g., `v1.0.0`) verified to originate from the `main` branch.
  * **Role:** Acts as the controller without building artifacts directly; orchestrates modular reusable workflows and passes cryptographic digests between them.
  * **Execution Flow:** Coordinates `_build-push.yml` ➔ `_sbom.yml` ➔ `_scan-gate.yml` ➔ **`SLSA L3 Provenance`** ➔ `_build-sign.yml`.
  * **Outcome:** Produces an immutable, fully-attested release package in Google Artifact Registry.

* **`_build-push.yml` (Immutable Container Build)**
  * **Trigger:** Called directly by `release.yml` (`workflow_call`).
  * **Authentication:** Passwordless OpenID Connect (OIDC) through Google Cloud Workload Identity Federation (WIF).
  * **Execution:**
    * Configures `Docker Buildx` with optimized multi-stage build caching.
    * Authenticates to Google Cloud using short-lived tokens issued via WIF.
    * Builds minimal distroless/non-root images for `zt-orders` and `zt-payments`.
    * Pushes container images exclusively by cryptographic digest (`push-by-digest=true`) to Google Artifact Registry, preventing mutable tag hijacking.
  * **Outcome:** Emits immutable SHA256 image digests (`orders_digest`, `payments_digest`) to downstream workflow steps.

* **`_sbom.yml` (Software Bill of Materials Generation)**
  * **Trigger:** Called upon successful completion of container builds in `_build-push.yml`.
  * **Execution:**
    * Authenticates to private Google Artifact Registry via WIF.
    * Runs `Syft` (Anchore) against the exact container digests to catalog all OS packages, Python dependencies, and licenses into **CycloneDX JSON** SBOMs (`sbom-*.cdx.json`).
    * Validates SBOM structure, schema completeness, and non-empty component listings with `jq`.
    * Saves SBOM files as pipeline artifacts for subsequent attestation stages.
  * **Outcome:** Generates verified CycloneDX software bill of materials ready for signing.

* **`_scan-gate.yml` (Dual-Engine Vulnerability Gate)**
  * **Trigger:** Called immediately after SBOM artifact creation in `_sbom.yml`.
  * **Execution:**
    * **Trivy (Aqua Security):** Scans images and enforces a zero-tolerance policy for unvetted critical vulnerabilities (**0 CRITICAL CVEs**). Emits a structured `cosign-vuln` report.
    * **Grype (Anchore):** Acts as an independent secondary scanner, cross-referencing the generated SBOM against its vulnerability feed to prevent scanner blind spots.
    * Stores machine-readable scan reports as job artifacts. It scans a specific image by downloading it locally, builds a list of all packages contained within, and checks each package against Anchore’s own vulnerability database.
  * **Outcome:** Serves as a hard gate; unaddressed critical CVEs immediately terminate the release pipeline before signing.

* **SLSA Build Level 3 Provenance (slsa-github-generator)**
  * **Trigger:** Orchestrated by `release.yml` immediately after passing `_scan-gate.yml`.
  * **Role:** An isolated, hardened reusable workflow from the SLSA Framework / OpenSSF (`generator_container_slsa3.yml`).
  * **Execution:** Generates a non-forgeable, cryptographically signed SLSA Build L3 provenance predicate containing exact build environment metadata, source commit SHA, and builder identity.
  * **Outcome:** Produces verifiable supply chain provenance required by Kyverno admission policies.

* **`_build-sign.yml` (Keyless Signing & Metadata Attestation)**
  * **Trigger:** Called only after images pass all vulnerability criteria and provenance generation.
  * **Security Profile:** Runs in the protected GitHub Environment `release`; granted scoped `id-token: write` permissions for Sigstore interactions.
  * **Execution:**
    * Retrieves vetted SBOMs and Trivy vulnerability reports from workflow artifacts.
    * Uses **Cosign** in keyless mode to cryptographically sign container digests using ephemeral certificates issued by Sigstore **Fulcio**.
    * Logs non-repudiable transparency records to Sigstore **Rekor**.
    * Attaches `cyclonedx` (SBOM), `vuln` (Trivy scan), and SLSA provenance in-toto attestations directly to the image manifests in Google Artifact Registry.
  * **Outcome:** Generates `.sig` and `.att` registry artifacts required by Kyverno admission controllers to permit cluster deployment.

* **`nightly.yml` (Continuous Security Audit & Drift Detection)**
  * **Trigger:** Runs daily on schedule at 02:00 UTC (`cron: 0 2 * * *`) or manually via `workflow_dispatch`.
  * **Execution:**
    * **Release Rescan:** Re-evaluates existing production image digests against updated CVE feeds. Automatically submits a pull request updating `security/revoked-digests.yaml` if newly published zero-day exploits impact running images.
    * **Security Baseline Drift Check:** Executes `scripts/policy-drift.sh` to compare repository settings, branch protections, and required reviews against `security/repo-baseline.json`.
    * **OpenSSF Scorecard:** Computes supply chain security posture scores and exports results to GitHub Security.
    * **Automated Red-Teaming:** Runs automated test scenarios (`RT-01` through `RT-14`) to verify detection and prevention layers across admission, runtime, and network policies.
  * **Outcome:** Detects configuration drift, emerging vulnerabilities, and policy bypass attempts proactively.

---

### Kyverno HA

Preview:
В саму архітектуру не включаємо в проєкт kyverno/kyverno-policies. Власні політики в platform/kyverno/policies/.
Опціонально підключаємо kyverno/policy-reporter окремим чартом для UI-інтеграції.

Role in project:
Головний Admission Controller кластера. Працює синхронно на вході в API Server (Fail-Closed). Перевіряє цифрові підписи Cosign, наявність та зміст атестацій (SBOM, 0 CRITICAL CVEs, вікно свіжості ≤ 72h), SLSA Build L3 provenance, блокує відкликані digest-и та примусово забезпечує стандарти Pod Security Standards (Restricted).
Розгортається в кластері у вигляді чотирьох контролерів. В проєкті надано 5 маніфестів політик ClusterPolicy.

---

### Falco & Falcosidekick

Preview:
Розгортається як DaemonSet на базі modern eBPF драйвера (без необхідності налагодження модулів ядра). Разом із Falco розгортається Falcosidekick у HA (2 репліки) для відправки подій у Loki та канали сповіщень. Правила безпеки розділені на модуль whitelist, власні нульової довіри (01-zero-trust.yaml) та тестові для red-team.

Role in project:
Останній рубіж захисту (Runtime Defense). Стежить за поведінкою контейнерів у реальному часі на рівні системних викликів ядра Linux:
1. Фіксує появу interactive shell (`sh`, `bash`) у запущених подах.
2. Блокує запуск пакетних менеджерів (`apt`, `apk`, `pip`) у продакшн-контейнерах.
3. Детектує спроби викрадення системного токена ServiceAccount (`/var/run/secrets/...`) та несанкціонований запис у системні папки (`/etc`, `/bin`, `/usr`).
4. Передає алерти у Falcosidekick ➔ Loki для аудиту та виступає тригером для ізоляції пода (карантин через Cilium) і відкликання паролів у Vault.
Працює з `privileged: false`, використовуючи виключно цільові Linux capabilities (`BPF`, `PERFMON`, `SYS_RESOURCE`, `SYS_PTRACE`, `DAC_READ_SEARCH`).


---

### Cert-manager

Preview:
Розгортається в HA (по 2 репліки на controller, webhook, cainjector) за стандартами Pod Security Standard Restricted (non-root, read-only rootfs, drop ALL capabilities). CRD встановлюються автоматично.

Role in project:
1. Захист Admission Webhooks (Kyverno, VSO, внутрішні CRD): K8s API Server спілкується з вебхуками виключно по mTLS. Підкомпонент `cainjector` автоматично підставляє актуальні CA бандли в конфігурації вебхуків.
2. Автоматична ротація X.509 сертифікатів без участі людини та виключення збоїв кластера через прострочений TLS.
3. Фундамент для шифрування трафіку між вузлами Vault HA та внутрішніми сервісами.

---

### HashiCorp Vault HA (Raft) & Vault Secrets Operator (VSO)

Що шифрується в проєкті:
1. Додаток:
  - zt-orders: динамічні креденшіали до PostgreSQL. Замість статичного пароля у змінних середовища чи конфіг-файлі — Vault генерує тимчасового користувача з TTL 15–60 хв. Додаток читає його з RAM-пам'яті /vault/secrets/db-creds.txt.
  - zt-payments: API ключі до платіжних шлюзів (External PSP API Keys)
2. Інфраструктура:
  - Root-пароль від PostgreSQL
  - Внутрішні TLS-сертифікати (PKI Secret Engine)
  - Master Key самого Vault (Auto-Unseal via Google Cloud KMS)

Компоненти: 
1. Сервер: HashiCorp Vault HA розгорнутий використовуючи platform/vault/custom.yaml.
Працює в кластері у власному просторі імен vault у кластерному режимі HA (3 репліки з Raft консенсусом). Увімкений трафік HTTPS між сервером вольт та його клієнтами.
Має увімкнений плагін баз даних: database secrets engine.
Після підняття серверу потрібне: підключення до бази PostgreSQL та увімкнення Kubernetes Auth

2. Політика безпеки: HCL Policy (platform/vault/policies/orders-rw.hcl)
Працює за принципом Least Privilege. Файл політики platform/vault/policies/orders-rw.hcl завантажується в сервер вольт. Це відбувається в скрипті scripts/setup-vault.sh.

3. Довіра: Kubernetes Authentication у Vault

4. Оператор: VSO (Vault Secrets Operator)
Розгортання двох реплік оператора для HA. А також завантаження CRD в кластер.
---

### Conftest (Open Policy Agent / Rego)

**Концепція та суть інструменту:**
Conftest — це легка утиліта статичного тестування конфігурацій за принципом **Policy-as-Code**, побудована на базі рушія **Open Policy Agent (OPA)** та декларативної мови запитів **Rego**. Вона дозволяє писати тести та перевірки безпеки для будь-яких структурованих текстових файлів (Kubernetes YAML, Terraform, Dockerfile, JSON).

**Роль у проєкті (Shift-Left Security):**
1. **Превентивний захист на етапі Git / CI:** Якщо Kyverno захищає кластер вже в момент деплою (останній рубіж), то Conftest зупиняє небезпечні маніфести **ще до злиття коду в `main` (Shift-Left)**.
2. **Перевірка Kubernetes-маніфестів (`apps/manifests/`):**
   * Заборона використання плаваючих тегів `:latest` (вимога точного закріплення за криптографічним хешем `@sha256:`).
   * Обов'язкова відповідність стандарту Restricted PSA (`runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `drop: ["ALL"]`, заборона ескалації привілеїв).
   * Обов'язкова наявність лімітів ресурсів (`cpu`, `memory`).
3. **Контроль дрифту налаштувань репозиторію (Security Baseline / RT-12):**
   * Звіряє конфігурацію GitHub Rulesets та гілок з еталонним файлом `security/repo-baseline.json`. Якщо хтось послабить захист гілки `main` або вимкне обов'язковий підпис комітів — Conftest у CI падає з помилкою.

**Як це працює на практиці:**
* Правила безпеки описуються декларативно у файлах `compliance/conftest/*.rego`.
* Під час створення Pull Request пайплайн `pr.yml` виконує команду `conftest test apps/manifests/`.
* Якщо маніфест містить порушення, розробник отримує миттєвий відгук із детальним поясненням помилки прямо в терміналі CI, не витрачаючи час на запуск кластера.

---

### Loki

---

### Cilium Policies (eBPF Zero-Trust Network Perimeter)
Preview:
Мережевий шар розгортається автоматично за допомогою GKE Dataplane V2 (`datapath_provider = "ADVANCED_DATAPATH"` у Terraform), який постачає керований Google Cilium на базі ядра eBPF без потреби ручного встановлення Helm-чарту. Усі 4 маніфести розташовані в директорії `platform/cilium/` і використовують нативний CRD `apiVersion: cilium.io/v2` (`kind: CiliumNetworkPolicy`).

Role in project:
Реалізує принцип «Default-Deny» та захист периметра на рівнях L3/L4/L7 моделі OSI, унеможливлюючи горизонтальне переміщення атакуючого (Lateral Movement) та витік секретів у мережу:

1. **`00-default-deny.yaml` (Базова залізна завіса):**
   * **Що робить:** Повністю блокує **100% вхідного (Ingress) та вихідного (Egress)** трафіку для будь-якого пода в просторі імен `zt-apps` (`endpointSelector: {}`).
   * **Навіщо:** Жоден новостворений або зламаний контейнер не має права надіслати чи отримати жодного байту мережевого трафіку без явного whitelist-дозволу.

2. **`01-dns-allow.yaml` (Контрольований системний DNS):**
   * **Що робить:** Дозволяє подам у `zt-apps` звертатися виключно до системного `kube-dns` у неймспейсі `kube-system` на 53 порт (UDP/TCP).
   * **Навіщо:** Оскільки `default-deny` відрубав усе, поди втрачають здатність резолвити адреси. Ця політика відновлює внутрішній DNS і вмикає DNS-проксі Cilium для наступного інспектування FQDN.

3. **`02-orders-to-payments-l7.yaml` (East-West L7 мікросервісний міст):**
   * **Що робить:** Надає гранулярний доступ між сервісами замовлень, платежів та базою даних:
     * **L7 HTTP enforcement:** Сервіс `zt-orders` може викликати `zt-payments` на порт 8080 **виключно через метод `POST /v1/charge`** та `GET /healthz`. Будь-який інший URL, метод (наприклад, `GET /admin` або `DELETE /v1/charge`) дропається eBPF на рівні ядра з відповіддю HTTP 403.
     * **Доступ до БД:** Дозволяє вихідний трафік від `zt-orders` до PostgreSQL (`postgres-rw` у неймспейсі `zt-data`) строго на порт 5432/TCP.

4. **`03-payments-tofqdns.yaml` (Контрольований вихід на платіжні шлюзи):**
   * **Що робить:** Дозволяє сервісу `zt-payments` виходити в інтернет **тільки на дозволені доменні імена (FQDN)** платіжних шлюзів (`api.psp.example`, `httpbin.org`) на порти 80/443.
   * **Навіщо:** Повністю блокує несанкціоновану ексфільтрацію даних та запити до метаданих Google Cloud (`169.254.169.254`), перекриваючи крадіжку хмарних токенів ноди.


---

### Trivy Operator

---

### kube-bench

---

### Kubescape

---

### WireGuard

---

### Hubble (Relay + UI)

---

### Cilium eBPF && Policies
Preview:
Керований GKE Dataplane V2 (`ADVANCED_DATAPATH` у Terraform), що розгортає Cilium eBPF на рівні ядра Linux без окремого Helm-чарту. Усі мережеві політики розташовані в `platform/cilium/` (`apiVersion: cilium.io/v2`).

Role in project:
1. **`00-default-deny.yaml`:** Повне блокування всього Ingress та Egress трафіку в `zt-apps` за замовчуванням.
2. **`01-dns-allow.yaml`:** Дозвіл виходу лише на `kube-dns` (порт 53) із активацією DNS-проксі Cilium.
3. **`02-orders-to-payments-l7.yaml`:** L7 HTTP фільтрація (`zt-orders` ➔ `zt-payments` лише `POST /v1/charge` та `GET /healthz`) + доступ до PostgreSQL (порт 5432).
4. **`03-payments-tofqdns.yaml`:** Whitelisting вихідного трафіку лише на дозволені домени платіжних шлюзів (`toFQDNs`) та блокування доступу до GCP metadata (`169.254.169.254`).

---

### Sigstore (Fulcio + Rekor)

---

### Catalog of Scripts

Усі автоматизовані скрипти платформи (розгорнуті та заплановані згідно з `PLAN.md`, `BASE.md`, `BASE-1.md`):

#### 1. Bootstrap, Infrastructure & Vault (`scripts/`)
* **`scripts/cluster-init.sh`** *(Реалізовано)* — головний оркестратор розгортання платформи з нуля на GKE: додає Helm-репозиторії, запускає Terraform (`tf/`), піднімає `cert-manager`, `Kyverno HA` (+ політики й винятки), `Falco + Falcosidekick`, `Trivy Operator`, `CloudNativePG`, `Vault HA`, `VSO` (+ CRD), `Grafana Loki`, активує `Hubble`, накладає `CiliumNetworkPolicy` та деплоїть мікросервіси `zt-orders` і `zt-payments`. Застосовується для повної інсталяції платформи у вже створеному заздалегідь кластері. 

* **`scripts/setup-vault.sh`** *(Реалізовано)* — ініціалізація та розпечатування (unseal) кластера HashiCorp Vault HA, увімкнення `Kubernetes Auth`, застосування least-privilege HCL-політики `orders-rw.hcl`, прив'язка ролі `orders-role` до `zt-orders-sa` та налаштування `PostgreSQL Database Secrets Engine` для видачі динамічних креденшіалів із TTL 1h і `revocation_statements`. Автоматично запускається під час етапу 9 виконання scripts/cluster-init.sh.

#### 2. Verification, Compliance & Drift Detection (`scripts/`)
* **`scripts/verify.sh`** *(Реалізовано)* — локальна/CI перевірка криптографічної цілісності образів: валідує безключовий підпис `Cosign` (OIDC identity + Rekor transparency log) та наявність атестацій (`SBOM`, `vuln`, `SLSA`). Необхідно передати повний шлях образу з @sha256.
* **`scripts/policy-drift.sh`** *(Заплановано / Порожній)* — перевірка дрифту налаштувань безпеки GitHub (Branch Protection, Tag Protection, Environments) через GitHub API шляхом звірки з еталоном `security/repo-baseline.json` (запускається в `nightly.yml`).
* **`scripts/gen-evidence.sh`** *(Заплановано / Порожній)* — генератор доказів комплаєнсу (команда `make compliance`): запускає аудит кластера через `kube-bench` (CIS Kubernetes Benchmark) та `Kubescape` (NSA-CISA / MITRE ATT&CK) і зберігає звіти в `docs/evidence/` та `compliance/`.

#### 3. Automated Red-Teaming (`redteam/`)
* **`redteam/run.sh`** *(Реалізовано)* — головний раннер автоматизованого Red-Team тестування (команда `make redteam`): знаходить і запускає всі сценарії `redteam/scenarios/RT-*/attack.sh`, підраховує `Passed/Failed` і повертає ненульовий код виходу при регресії захисту.
* **`redteam/scenarios/RT-01..RT-14/attack.sh`** *(Заплановано / `BASE.md`, `PLAN.md`)* — 14+ автоматизованих сценаріїв атак на кожен шар довіри (непідписані образи, підміна дайджесту, відсутність SBOM/provenance, `:latest` тег, `root`/`privileged` поди, обхід Cilium L7/FQDN, звернення до GCP metadata `169.254.169.254`, запуск `sh/bash` у контейнері, використання відкликаних DB-кредів Vault).
* **`redteam/ztrt/`** *(Заплановано / `BASE-1.md`)* — розширений Python/Go runner для декларативних YAML-сценаріїв (`RT-01..RT-26` + позитивні контролі `P-01..P-03`), збору доказів (Kyverno events, Hubble `DROPPED` flows, Falco alerts) та генерації JUnit/Markdown звітів.


---

### Chaos Engineering && Security tests
