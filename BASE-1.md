Zero-Trust Software Supply Chain Platform — повна специфікація
DevSecOps-флагман для резюме. Хмара: GKE (тільки). Теза: жоден артефакт, ідентичність чи мережевий шлях не получають довіри за замовчуванням; кожен перехід верифікується криптографічно і політикою, а ефективність доводиться red-team тестами.
0. Що проєкт доводить
1. Походження артефакта доведене: кожен образ має keyless-підпис, SLSA provenance, SBOM і scan-атестацію, прив'язані до репо, workflow і ref.
2. Кластер не запускає нічого без доказів: Kyverno verifyImages перевіряє підпис, identity, provenance, SBOM і vuln-gate на admission.
3. Zero trust у runtime: default-deny мережа (Cilium), короткоживучі креденшіали (Vault), runtime-детект і автореакція (Falco).
4. Все це верифіковано: red-team suite із десятками сценаріїв, кожен з очікуваним шаром блокування, звіт у CI.
Не-цілі: не «набір безпекових інструментів», не бізнес-логіка платежів. Цінність у ланцюгу довіри end-to-end і у доказах, що атаки блокуються.
1. Цільова система
• Платіжно-подібний застосунок з PCI-DSS framing: api (FastAPI), payments (FastAPI, симульовані токенізовані платежі, карток немає), ledger-worker, PostgreSQL (CloudNativePG). Три сервіси потрібні, щоб показати east-west політики.
• Зовнішня залежність: симульований PSP по FQDN (для egress-політик).
• Додаток свідомо малий. Фокус на ланцюгу, а не на коді.
2. Модель загроз і контролів
Рядок — одна загроза, контроль, і намагабований тест у red-team suite (розділ 11).
Зона
Загроза
Контроль
RT
Source
Обхід review, force push, непідписані коміти
Branch protection/rulesets, required reviews, CODEOWNERS, signed commits (gitsign)
01
Source
Викрадений токен мейнтейнера
2FA, короткі токени, GITHUB_TOKEN read-only за замовчуванням, environment protection
01, 02
Build
Зловмисний PR з форка
pull_request без секретів і без id-token
02
Build
Змінений workflow на фіча-гілці підписує образ
Identity у сертифікаті Fulcio містить ref; Kyverno вимагає refs/heads/main
03
Build
Компрометована GitHub Action
Всі actions pinned за SHA, allowlist, Harden-Runner (egress), zizmor/pinact у CI, Scorecard
26
Build
Підробка provenance
Provenance генерує ізольований reusable workflow (slsa-github-generator), builder identity верифікується в Kyverno
07, 08
Dependency
Typosquat / dependency confusion
Hash-pinned lockfile (--require-hashes), dependency-review, Renovate
25
Dependency
Відомі CVE
Trivy/Grype gate, SBOM, періодичний rescan
09
Base image
Mutable tag, підміна base
Pin за digest, верифікація підпису base у CI, Renovate digest PR
06
Artifact
Непідписаний образ у registry
verifyImages required
04
Artifact
Образ, підписаний чужою identity
Subject = конкретний workflow@ref, issuer GitHub
05
Artifact
Retag/підміна після підпису
Deploy лише за digest, immutable tags, mutateDigest
06, 11
Deploy
Обхід GitOps (kubectl apply)
RBAC, Argo CD як єдиний writer, admission застосовується всім
23
Runtime
privileged / hostPath / root
PSS restricted + Kyverno
12, 13
Runtime
Lateral movement
Cilium default-deny + L3/L4/L7 allow-list
14
Runtime
Exfiltration / metadata server
FQDN egress allow-list, блок metadata, Workload Identity
15, 16
Runtime
Викрадені DB-креди
Vault dynamic creds TTL 15 хв, revoke lease
17, 18
Runtime
RCE: shell, miner, читання SA token
Falco + авто-карантин
19–22
Platform
Admission webhook мертвий
failurePolicy: Fail, HA, PDB, моніторинг
24
3. Архітектура і trust boundaries
 Dev -> GitHub (rulesets, signed commits, CODEOWNERS)
          |  TB1: source -> build
          v
  GitHub Actions: release.yml (pinned actions, Harden-Runner)
    build -> push by digest -> Artifact Registry (WIF, immutable tags)
    syft SBOM, trivy scan
    slsa-github-generator (isolated reusable workflow) -> provenance
    cosign sign (keyless, Fulcio cert bound to workflow@ref) -> Rekor log
    cosign attest: SBOM, vuln, provenance
          |  TB2: build -> registry
          v
  Argo CD (GitOps, only writer) --manifests reference image@sha256--
          |  TB3: registry -> cluster
          v
 GKE private cluster
 +----------------------------------------------------------------------+
 | Kyverno admission: verifyImages + PSS + digest + exceptions          |
 | Cilium: default-deny, L7 allow-list, FQDN egress, WireGuard, Hubble  |  TB4: pod -> pod
 | Vault (HA Raft, KMS auto-unseal) -> dynamic DB creds -> CNPG         |  TB5: pod -> data
 | Falco (eBPF) -> sidekick -> responder: quarantine + revoke leases    |  TB6: runtime behaviour
 +----------------------------------------------------------------------+
  red-team suite (Jobs): attacks at every TB, asserts block/detect
Кожна межа верифікується незалежно: підпис не замінює admission, admission не замінює мережеву сегментацію, мережа не замінює runtime-детект. Це defense in depth, а не одна велика брама.
4. Стек
Шар
Інструмент
Роль
Cloud/IaC
GKE Standard (private nodes, Shielded, Workload Identity), Terraform, Cloud KMS, Artifact Registry
Кластер, реєстр, auto-unseal Vault, envelope encryption секретів
CI
GitHub Actions + OIDC → WIF, Harden-Runner, zizmor, pinact, Renovate
Збірка без довгоживучих ключів, гігієна workflow
Code/dep scanning
Semgrep або CodeQL, gitleaks, dependency-review, Trivy/Grype
SAST, секрети, CVE
SBOM
Syft (CycloneDX або SPDX)
Інвентаризація компонентів
Provenance
slsa-github-generator (container, L3), slsa-verifier
Build provenance, верифікація в CI
Signing
cosign keyless (Fulcio, Rekor, OIDC GitHub)
Підпис і атестації
GitOps
Argo CD
Єдиний шлях деплою
Admission
Kyverno (verifyImages, validate, mutate, generate), Kyverno CLI/Chainsaw для тестів
Верифікація доказів і політики подів
Network
Cilium (або GKE Dataplane V2, ADR-005), Hubble, WireGuard
Default-deny, L7, FQDN, докази потоків
Secrets
Vault HA (Raft), Cloud KMS auto-unseal, K8s auth, DB secrets engine, Vault Secrets Operator
Dynamic creds, audit
Runtime
Falco (modern eBPF) + Falcosidekick, автореакція (власний responder або Falco Talon)
Детект і реакція
DB
CloudNativePG
Ціль dynamic creds
Observability
Prometheus/Grafana, Loki
Метрики політик, логи подій, докази
Policy tests
Kyverno CLI test, Chainsaw, conftest (Terraform/manifests)
Політики як код з тестами
Red-team
Власний набір ztrt (Python або Go) + Kubernetes Jobs
Атаки та асерти
Версії pinned і перевірені на актуальність на старті. Поведінка cosign між мажорними версіями змінюється (формат bundle, прапори), і це має бути зафіксовано у CI та в політиках.
5. Build-сторона: pipeline
5.1 Етапи
1. Checkout з persist-credentials: false, всі actions pinned за SHA, permissions: {} на рівні workflow, далі точково на job.
2. Залежності тільки з hash-lock (pip install --require-hashes або uv lock), dependency-review на PR.
3. Тести, SAST (Semgrep/CodeQL), gitleaks.
4. Build образу: minimal/distroless base, pinned за digest, верифікація підпису base через cosign (якщо він її має), multi-stage, non-root, без shell/package manager у runtime-шарі. Push за digest.
5. SBOM (Syft) і vuln scan (Trivy) по digest. Gate: critical з доступним fix → fail.
6. Provenance через slsa-github-generator (окремий reusable workflow, ізольований від коду збірки).
7. cosign sign (keyless) і cosign attest (SBOM, vuln) тільки в job з id-token: write і environment: release.
8. Верифікація після підпису в CI (cosign verify, slsa-verifier verify-image) як smoke test тієї ж політики, що буде в кластері.
9. Оновлення маніфеста у deploy-путі image@sha256:... (PR або коміт бота), Argo CD синхронізує.
5.2 Скелет release workflow
name: release
on:
  push:
    branches: [main]
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    permissions: {contents: read, id-token: write}   # id-token лише для WIF в Artifact Registry
    outputs:
      digest: ${{ steps.push.outputs.digest }}
    steps:
      - uses: step-security/harden-runner@<sha>        # egress: block + allowlist
      - uses: actions/checkout@<sha>
        with: {persist-credentials: false}
      - uses: google-github-actions/auth@<sha>         # WIF, без JSON-ключів
      - run: pip install --require-hashes -r requirements.lock
      - run: pytest && semgrep ci && gitleaks detect
      - uses: docker/build-push-action@<sha>
        id: push
      - run: syft $IMAGE@${{ steps.push.outputs.digest }} -o cyclonedx-json > sbom.cdx.json
      - run: trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed $IMAGE@${{ steps.push.outputs.digest }}
  provenance:
    needs: build
    permissions: {actions: read, id-token: write, packages: write}
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@<tag>
    with:
      image: ${{ vars.IMAGE }}
      digest: ${{ needs.build.outputs.digest }}
  sign-attest:
    needs: [build, provenance]
    runs-on: ubuntu-latest
    environment: release
    permissions: {id-token: write}
    steps:
      - run: cosign sign --yes $IMAGE@$DIGEST
      - run: cosign attest --yes --type cyclonedx --predicate sbom.cdx.json $IMAGE@$DIGEST
      - run: cosign attest --yes --type vuln --predicate trivy.json $IMAGE@$DIGEST
      - run: cosign verify --certificate-identity $WORKFLOW_ID --certificate-oidc-issuer https://token.actions.githubusercontent.com $IMAGE@$DIGEST
5.3 Підводні камені
• Підписуй за digest, не за tag. Підпис на tag нічого не гарантує: tag можна перевести.
• slsa-github-generator потрібно викликати за tag, а не SHA: він вимагає цього для верифікації builder identity. Це єдиний виняток з правила «все за SHA», задокументуй його у ADR-003, інакше zizmor/pinact зроблять з нього false positive.
• Дві різні identity. Образ підписує ваш release.yml@refs/heads/main, а provenance-атестацію підписує reusable workflow генератора. Kyverno-політика має приймати різні attestors для підпису і для provenance. Це найчастіша помилка при першій налаштовці.
• id-token: write лише в job-ах, де воно нужно, і ніколи на подіях з форків.
• Вимога SLSA L3 відноситься до Build track. Вона гарантує походження артефакта, а не доброзичливість коду. Це треба сказати вголос у README (див. розділ «Обмеження»).
• Immutable tags у Artifact Registry увімкни, якщо доступно (перевір актуальну підтримку).
6. Admission: Kyverno
6.1 Головна політика verifyImages
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: verify-supply-chain}
spec:
  validationFailureAction: Enforce
  background: false
  webhookConfiguration: {failurePolicy: Fail, timeoutSeconds: 30}
  rules:
    - name: verify-signature-provenance-sbom-vuln
      match:
        any:
          - resources: {kinds: [Pod], namespaces: [payments-prod, payments-stage]}
      verifyImages:
        - imageReferences: ['europe-docker.pkg.dev/<project>/payments/*']
          required: true
          mutateDigest: true
          verifyDigest: true
          attestors:
            - entries:
                - keyless:
                    issuer: https://token.actions.githubusercontent.com
                    subject: https://github.com/<org>/zt-supply-chain/.github/workflows/release.yml@refs/heads/main
                    rekor: {url: https://rekor.sigstore.dev}
          attestations:
            - type: https://slsa.dev/provenance/v0.2
              attestors:
                - entries:
                    - keyless:
                        issuer: https://token.actions.githubusercontent.com
                        subject: https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/<tag>
                        rekor: {url: https://rekor.sigstore.dev}
              conditions:
                - all:
                    - key: '{{ invocation.configSource.uri }}'
                      operator: Equals
                      value: git+https://github.com/<org>/zt-supply-chain@refs/heads/main
            - type: https://cyclonedx.org/bom
              attestors:
                - entries:
                    - keyless:
                        issuer: https://token.actions.githubusercontent.com
                        subject: https://github.com/<org>/zt-supply-chain/.github/workflows/release.yml@refs/heads/main
                        rekor: {url: https://rekor.sigstore.dev}
Попередження: тип і структура provenance-предиката залежать від версії генератора (v0.2 або v1) і доступ до полів у conditions залежить від версії Kyverno. Перевір на фактичних версіях і закріпи тести (розділ 6.4), а не переписуй з пам'яті. Vuln-атестація (https://cosign.sigstore.dev/attestation/vuln/v1) підключається так само з умовою «немає critical з fix».
6.2 Решта політик
Політика
Що робить
Require digest
Забороняє tag-посилання без digest, mutate до digest там, де дозволено
Restrict registries
Тільки наш Artifact Registry і allowlist системних образів
PSS restricted
validate.podSecurity (restricted), у kube-system винятки
Hardening
runAsNonRoot, readOnlyRootFilesystem, drop ALL capabilities, seccompProfile RuntimeDefault, без hostPath/hostNetwork/privileged
Resources
Вимагає requests/limits
ServiceAccount
automountServiceAccountToken: false, окрім явного allowlist
Namespace baseline (generate)
Для кожного нового namespace автоматично створює default-deny мережеву політику й labels
Exceptions
Тільки через PolicyException з owner, терміном і issue; метрика кількості винятків
6.3 Операційні ризики admission (ADR-004)
• failurePolicy: Fail безпечніше, але Kyverno стає SPOF. Мітигація: 3 репліки, PDB, anti-affinity, priorityClass, ресурси, виключення kube-system і самого Kyverno з webhook, моніторинг латентності й помилок webhook.
• Bootstrap: образи Kyverno і самої платформи верифікуються окремою політикою/позасмуговою перевіркою в CI, інакше курка-яйце.
• Затримка: перевірка підпису ходить у registry/Rekor. Використовуй cache Kyverno і перевіряй вплив на час старту подів.
• Залежність від публічного Sigstore (Fulcio/Rekor/TUF root). Для демо прийнятно, у продакшні розглядають private Sigstore (stretch).
6.4 Тестування політик
• Kyverno CLI test на фікстурах: pass-кейс і кожен fail-кейс (неправильний subject, відсутній SBOM, tag замість digest тощо).
• Chainsaw e2e у kind: реальне створення подів проти політик.
• Для кожного exception-кейсу є тест, що без PolicyException блокується.
7. Мережа: Cilium
• Default-deny ingress і egress для namespace застосунку (CiliumClusterwideNetworkPolicy/NetworkPolicy), з явним дозволом DNS до kube-dns.
• Allow-list east-west: api → payments лише POST /v1/charge (L7 HTTP), payments → postgres:5432, ledger-worker → postgres:5432. Все інше drop.
• Egress через FQDN: payments → лише toFQDNs симульованого PSP. Блок metadata-сервера GKE (169.254.169.254) для застосункових подів, доступ до хмарних API лише через Workload Identity там, де це справді потрібно.
• Шифрування вузол–вузол: WireGuard (прозоре шифрування Cilium).
• Hubble як джерело доказів: flows з вердиктом DROPPED потрапляють у звіт red-team suite.
• Mutual auth (SPIFFE/SPIRE у Cilium): на момент старту перевір зрілість функції в поточних docs; трактуй як stretch/experimental, а не як основу довіри. Базова ідентичність підів у цьому проєкті — Cilium identity + Kubernetes ServiceAccount.
• Карантин: політика, що ізолює поди з лейблом quarantine=true (drop усього, окрім збору логів), на неї спирається responder з розділу 9.
ADR-005: GKE Dataplane V2 (керований Cilium) простіший і підтримується Google, але має обмеження щодо CiliumNetworkPolicy/L7/Hubble-функцій. Self-managed Cilium дає L7, повний Hubble, FQDN, WireGuard, але ти відповідаєш за сумісність із GKE і оновлення. Для флагмана, що показує Cilium, обирай self-managed, документуй компроміс.
8. Секрети: Vault
8.1 Топологія
• Vault HA, Raft storage, 3 репліки, TLS, auto-unseal через Cloud KMS, audit device (stdout → Loki або в GCS).
• Kubernetes auth: роль прив'язана до ServiceAccount і namespace (bound_service_account_names, bound_service_account_namespaces), короткий TTL токена.
• Політики за принципом найменших прав: сервіс payments читає тільки database/creds/payments-rw.
8.2 Dynamic DB credentials
vault secrets enable database
vault write database/config/payments-pg \
  plugin_name=postgresql-database-plugin \
  allowed_roles=payments-rw \
  connection_url='postgresql://{{username}}:{{password}}@payments-pg-rw.payments-prod:5432/payments?sslmode=require' \
  username=vault-admin password=$VAULT_ADMIN_PW
vault write -f database/rotate-root/payments-pg
vault write database/roles/payments-rw \
  db_name=payments-pg default_ttl=15m max_ttl=1h \
  creation_statements=@create.sql revocation_statements=@revoke.sql
create.sql: роль з VALID UNTIL і мінімальні GRANT (SELECT/INSERT на потрібні таблиці). revoke.sql: REASSIGN OWNED/DROP ROLE або примусове завершення сесій. Root-пароль vault-admin ротується одразу після конфігурації, щоб людина його не знала.
8.3 Доставка в под
• Vault Secrets Operator: VaultAuth + VaultDynamicSecret → Kubernetes Secret, rolloutRestartTargets або перепідключення застосунку при ротації.
• Складність, яку треба вирішити, а не замовчати: пул з'єднань і ротація. TTL 15 хв означає, що застосунок мусить переоткривати з'єднання (max lifetime пулу < TTL, обробка auth failure з retry). Без цього dynamic creds ламають продакшн. Це окремий тест (P-03).
• Revoke: при спрацюванні Falco responder викликає vault lease revoke -prefix database/creds/payments-rw, і вкрадені креди мертві негайно.
ADR-006: чому Vault, а не Secret Manager + Workload Identity: dynamic creds, lease revoke, audit на рівні кожного отримання, єдиний механізм для БД/PKI. Ціна: ти оператор Vault (HA, unseal, upgrades, бекапи Raft). Це треба визнати в ADR.
9. Runtime: Falco і реакція
9.1 Розгортання
• Falco DaemonSet із modern eBPF драйвером (потрібен GKE Standard, Autopilot не підходить), Falcosidekick → Slack і Loki, метрики в Prometheus.
• Налаштований набір правил: базові правила Falco + власні для payments-prod, шум відфільтровано allowlist-ами, інакше правила глушать.
- rule: Shell in payments container
  desc: Інтерактивний shell у контейнері застосунку
  condition: spawned_process and container and proc.name in (sh, bash, ash) and k8s.ns.name in (payments-prod)
  output: Shell spawned (user=%user.name pod=%k8s.pod.name ns=%k8s.ns.name cmd=%proc.cmdline image=%container.image.repository)
  priority: WARNING
  tags: [zt-supply-chain, mitre_execution]
9.2 Правила, що покривають red-team
Правило
Сценарій
Shell/exec у контейнері
RT-19
Запис у /usr, /bin, /etc і запуск щойно записаного бінарника
RT-20
Вихідне з'єднання поза allowlist, патерни майнера
RT-21
Читання service account token не-застосунковим процесом
RT-22
Запит до metadata-сервера
RT-15
9.3 Автореакція
Falco → Falcosidekick → webhook → responder (власний невеликий сервіс або Falco Talon):
1. Лейбл quarantine=true на под (Cilium ізолює мережу).
2. Revoke Vault leases цього сервісу.
3. Подія в Slack і GitHub issue з контекстом (под, образ digest, rule, час).
4. Под не видаляється одразу: потрібен для forensic. Опційно знімок логів.
Метрика якості: час від дії атакуючого до ізоляції (ціль для демо — десятки секунд).
10. Базовий hardening GKE
• Private nodes, master authorized networks, Shielded GKE nodes, Container-Optimized OS, release channel.
• Workload Identity (без node SA з широкими правами, без JSON-ключів); окремий мінімальний node SA.
• Application-layer secrets encryption через Cloud KMS.
• Cloud Audit Logs увімкнені, експорт у GCS/Loki для доказів.
• Artifact Registry: IAM за принципом найменших прав (CI лише push через WIF, вузли лише pull), Artifact Analysis як додатковий сигнал.
• Binary Authorization як опційний другий шар (defense in depth) поверх Kyverno, але не замість: дві системи політик дублюють підтримку, тож вирішуй свідомо (stretch).
11. Red-team suite (ztrt)
11.1 Дизайн
• Сценарії декларативні (YAML): id, опис, кроки атаки, очікуваний шар блокування, очікуване повідомлення/вердикт, ліміт часу, збір доказів.
• Виконання: Kubernetes Jobs у кластері + CLI для CI-частини. PASS означає, що атаку заблоковано або виявлено в очікуваному шарі за очікуваний час.
• Докази: Kyverno events/policy reports, Hubble flows (DROPPED), Falco alerts, Vault audit log, відповіді API-сервера. Зберігаються як artifact звіту.
• Негативні контролі (P-кейси): законний реліз проходить end-to-end, законний rollout проходить, ротація Vault creds не ламає застосунок. Без них suite винагороджує «заблокуй усе».
• Запуск: на кожен PR до політик (kind + Chainsaw), нічний прогін на ефемерному GKE, бейдж і Markdown/JUnit звіт у README.
11.2 Каталог сценаріїв
ID
Атака
Очікуваний шар
RT-01
Push непідписаного коміту / в обхід review у protected branch
Rulesets GitHub
RT-02
PR із форка намагається витягти секрети/id-token
Workflow permissions (немає токена)
RT-03
Змінений workflow на фіча-гілці підписує образ
Kyverno (subject ≠ main)
RT-04
Образ без підпису в registry
Kyverno verifyImages
RT-05
Образ, підписаний чужою keyless-identity (інший репо)
Kyverno (subject mismatch)
RT-06
Retag: digest підмінено після підпису
Підпис не валідний для нового digest, Kyverno
RT-07
Образ підписаний, але без provenance
Kyverno attestations
RT-08
Provenance з іншого репо/гілки
Kyverno conditions
RT-09
Образ із critical CVE (vuln-атестація)
Kyverno vuln-gate
RT-10
Образ без SBOM-атестації
Kyverno attestations
RT-11
Деплой за mutable tag latest
Require digest / mutateDigest
RT-12
privileged, hostPath, hostNetwork
PSS + Kyverno
RT-13
root, writable rootfs, без drop capabilities
Kyverno
RT-14
Под в payments ходить до чужого namespace
Cilium (DROPPED у Hubble)
RT-15
Запит до metadata-сервера
Cilium + Falco
RT-16
Egress/DNS-ексфільтрація поза allowlist
Cilium FQDN
RT-17
Використання DB-кредів після TTL/revoke
Postgres відмовляє
RT-18
Читання Vault-секрету поза політикою
Vault 403 + audit
RT-19
kubectl exec / shell у поді
Falco + карантин
RT-20
Запис і запуск бінарника в контейнері
readOnlyRootFilesystem + Falco
RT-21
Поведінка майнера (з'єднання на пул)
Cilium + Falco
RT-22
Читання SA token і виклик API-сервера
RBAC/automount off + Falco
RT-23
kubectl apply повз Argo CD
RBAC + admission
RT-24
Kyverno недоступний: чи є обхід
failurePolicy: Fail, подів не створюється
RT-25
Нова залежність без хешу / typosquat
CI: --require-hashes, dependency-review
RT-26
Action за tag замість SHA
CI: zizmor/pinact
P-01
Легітимний реліз end-to-end
Проходить
P-02
Легітимний rollout
Проходить
P-03
Ротація Vault creds під навантаженням
Без помилок застосунку
11.3 Метрики
• % сценаріїв, що заблоковані в очікуваному шарі, і окремо % заблокованих не там, де очікувалось (сигнал дрейфу архітектури).
• Час виявлення/ізоляції для runtime-сценаріїв (RT-19..22).
• False positives на P-кейсах і шум Falco за добу.
• Матриця покриття: загроза з розділу 2 ↔ сценарій ↔ шар.
12. Структура репозиторію
zt-supply-chain/
├── README.md                    # діаграма, trust boundaries, звіт red-team, SLSA self-assessment
├── docs/
│   ├── threat-model.md
│   ├── adr/                     # 001..012 (MADR)
│   ├── slsa-self-assessment.md
│   ├── limitations.md
│   └── runbooks/                # Kyverno down, Vault sealed, Falco storm, key/identity rotation
├── app/{api,payments,ledger-worker}/
├── infra/terraform/{modules,envs}/   # gke, network, kms, registry, wif, vault-infra
├── .github/
│   ├── workflows/{ci,release,policy-tests,redteam-nightly}.yml
│   └── CODEOWNERS, rulesets, renovate.json
├── deploy/
│   ├── argocd/
│   ├── platform/{kyverno,cilium,vault,vso,falco,cnpg}/
│   └── apps/
├── policies/
│   ├── kyverno/                 # ClusterPolicy + PolicyException шаблони
│   ├── network/                 # Cilium політики, quarantine
│   ├── tests/{cli,chainsaw}/
│   └── conftest/                # перевірки Terraform/маніфестів
├── falco/{rules,responder}/
└── redteam/
    ├── scenarios/*.yaml
    ├── ztrt/                    # runner, evidence collectors, report generator
    └── fixtures/                # погані образи, зламані workflow
13. Середовища і вартість
• Один GKE Standard private кластер (платформа + payments-stage + payments-prod як namespaces). Red-team деструктивні сценарії біжать у payments-stage і ефемерному кластері.
• Вартість: GKE-вузли (3–4), Vault HA, Falco DaemonSet, KMS, Artifact Registry. Порядок десятків доларів на тиждень при постійній роботі, точніше порахуй у GCP Pricing Calculator. Піднімай на сесії, Terraform teardown у CI, red-team nightly на ефемерному кластері.
• Для швидкого циклу політик використовуй kind + Chainsaw локально/в CI, GKE лише для інтеграції.
14. План по етапах із acceptance criteria
Етап
Зміст
Acceptance criteria
0. Foundation
Terraform: GKE hardened, KMS, Artifact Registry, WIF; Argo CD bootstrap; rulesets і CODEOWNERS
terraform apply з CI без ключів; кластер private; root app Synced
1. App + hardened CI
3 сервіси, hash-lock, SAST/gitleaks, pinned actions, Harden-Runner, zizmor, Scorecard
CI падає на action за tag і на залежності без хешу (RT-25/26)
2. Provenance + signing
SBOM, Trivy gate, slsa-github-generator, cosign keyless, атестації, verify у CI
cosign verify і slsa-verifier проходять на digest; Rekor-запис є
3. Admission
Kyverno HA, verifyImages, PSS, digest, exceptions, CLI/Chainsaw тести
RT-03..13 і RT-23/24 PASS
4. Network
Cilium default-deny, L7, FQDN, WireGuard, Hubble, quarantine policy
RT-14..16 PASS, доказ у Hubble
5. Secrets
Vault HA + KMS unseal, K8s auth, DB engine, VSO, ротація
RT-17/18 і P-03 PASS
6. Runtime
Falco rules, sidekick, responder (quarantine + lease revoke)
RT-19..22 PASS, ізоляція за ціль у секундах
7. Red-team suite
Runner, докази, звіт, nightly в CI, бейдж
Звіт із матрицею покриття; P-01..03 зелені
8. Подача
Threat model, SLSA self-assessment, ADR, limitations, runbooks, 5-хв демо
Рекрутер за 2 хв бачить ланцюг і цифри
Stretch: private Sigstore (Scaffolding), OpenVEX, Tetragon, SPIRE mutual auth, Binary Authorization як другий шар, GUAC, моніторинг Rekor, Harbor-міррор, перевірка reproducible builds, політики Argo CD щодо дозволених source-репо.
Орієнтир: 8–10 тижнів неповної зайнятості. Етапи 0–3 дають мінімально сильну версію, 4–7 перетворюють її на флагман.
15. Ключові ADR
ADR
Рішення
Обґрунтування / компроміс
001
Keyless підписи
Нема довгоживучих ключів, identity = workflow@ref. Мінус: залежність від Fulcio/Rekor/TUF, інформація про репо в публічному Rekor
002
Kyverno замість Sigstore policy-controller / Binary Authorization
Одна система для verify+validate+mutate+generate. Binary Authorization — GKE-native, але вужча
003
slsa-github-generator замість лише GitHub native attestations/Tekton Chains
Явна L3-модель із ізольованим builder і verifier. Виняток із pin за SHA задокументовано
004
failurePolicy: Fail + HA Kyverno
Безпека понад доступність, мітигації в 6.3
005
Self-managed Cilium vs GKE Dataplane V2
L7/Hubble/FQDN проти простоти
006
Vault vs Secret Manager
Dynamic creds, lease revoke, audit; ціна — операційний тягар
007
Vault Secrets Operator замість Agent injector/CSI
CRD-модель, rollout restart, менше sidecar-ів
008
Deploy за digest + immutable tags
Тег — не ідентичність
009
Falco замість Tetragon
Зріла екосистема правил; Tetragon — stretch з enforcement на рівні ядра
010
Red-team suite як код і джерело істини
Захист доведений тестами, не заявою
011
Лише GKE
Глибина замість мульти-хмарності
012
Публічний Sigstore для демо
Простота; private Sigstore описаний як future work
16. Обмеження (чесно, у README)
• SLSA Build L3 доводить походження артефакту, а не те, що код нешкідливий. Зловмисний коміт, що пройшов review, буде належно підписаний.
• Публічний Rekor зберігає інформацію про identity/репо. Для приватного коду це не варіант без private Sigstore.
• Доступність Sigstore (Fulcio/Rekor/TUF) входить у критичний шлях верифікації.
• Kyverno webhook — одночасно SPOF і поверхня атаки. Винятки (PolicyException) з часом ерозують модель, тому в них є owner і термін.
• L7 політики Cilium бачать HTTP лише там, де трафік не шифрований у поді або термінується проксі. Це треба врахувати в дизайні.
• Falco: якість визначається налаштуванням, дефолтні правила шумні.
• Vault: операційна складність і взаємодія dynamic creds з пулами з'єднань.
• Зовнішні залежності (базові образи, GitHub-hosted runners) лишаються довіреною базою; проєкт зменшує, а не усуває довіру.
17. Як це подавати
Bullets для резюме (підстав виміряні цифри)
• Побудував end-to-end ланцюг довіри (SLSA Build L3 provenance, cosign keyless, SBOM/vuln-атестації) з перевіркою на admission (Kyverno): блокується <N> із <M> атак supply-chain сценаріїв.
• Реалізував zero-trust runtime: Cilium default-deny з L7/FQDN політиками, Vault dynamic DB credentials (TTL 15 хв), Falco з автоматичною ізоляцією за <X> с.
• Створив red-team suite (<M> сценаріїв + позитивні контролі), що щоночі доводить ефективність контролів і дає матрицю покриття загроз.
Питання на співбесіді
• Що саме доводить SLSA L3, а що ні? Чому підписаний образ усе одно може бути шкідливим?
• Чому keyless і які ризики (Rekor, Fulcio, TUF)? Що якщо Sigstore недоступний?
• Чому дві різні identity (образ і provenance) у політиці?
• Чому підпис за digest, а не за tag?
• Що буде, якщо Kyverno впаде? Чому Fail і як ви це мітигуєте?
• Як динамічні креди працюють з пулом з'єднань?
• Чим Cilium L7 політика краще за NetworkPolicy і де її межі?
• Як ви довели, що контролі працюють, а не просто задекларовані?
• Які винятки в політиках і як ви не даєте їм розповзтись?
Поза скоупом
Мульти-хмара, повний service mesh, WAF/DDoS, DAST, управління ідентичностями користувачів, повноцінна відповідність PCI-DSS (використовується лише як framing, а не як заява про сертифікацію).
