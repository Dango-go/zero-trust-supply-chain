# Secrets Inventory & Key Management

Under the Zero-Trust architecture, long-lived static secrets are strictly eliminated from application workloads. Where static secrets are technically unavoidable (e.g. bootstrap/unseal), they are explicitly documented, isolated, and governed by strict compensating controls.

## Secrets Register

| Secret | Storage / Provider | Static? | Rotation Mechanism / Compensating Control |
| :--- | :--- | :--- | :--- |
| **GHCR CI Token** | GitHub Actions (`GITHUB_TOKEN`) | No | Ephemeral per-job token with least-privilege permissions. |
| **Release Signing Key** | Sigstore Fulcio Ephemeral X.509 Certificate | No | Keyless OIDC issuance (valid for ~10 minutes). Logged in Rekor. |
| **PostgreSQL App Credentials** | HashiCorp Vault Database Secrets Engine | No | Dynamically generated on-demand. Default TTL: 1h, Max TTL: 24h. Auto-renewed by Vault Secrets Operator (VSO). |
| **Internal TLS Certificates** | HashiCorp Vault PKI Engine | No | Short-lived certificates issued via cert-manager Vault Issuer. Automatic rotation before expiry. |
| **Vault Root PG Password** | Vault Internal Storage | Yes | Rotated immediately upon configuration via Vault `rotate-root`. Unknown to operators. |
| **Vault Unseal Key** | Dev: K8s Secret (Documented Risk) / Prod: Cloud KMS | **Yes (Dev)** | **Deliberate dev-environment risk** (ADR-0013). Production relies on Cloud KMS auto-unseal. |
| **Falcosidekick Slack Webhook** | Vault KV v2 → VSO | Yes | Stored securely in Vault; manual rotation with audit logging. |
