# ADR-0001: Keyless Image Signing and Attestations via Sigstore Cosign

* **Status:** Accepted
* **Date:** 2026-11-04
* **Deciders:** Core Maintainers

## Context
Deploying software into a Zero-Trust Kubernetes cluster requires verifiable proof of integrity and origin. Traditional signature models rely on long-lived private keys stored in CI secrets, introducing significant key management overhead, rotation risks, and potential compromise vectors.

## Considered Options
1. **Traditional Private Key Signing (GPG / Cosign Private Key):** Stored in GitHub Secrets.
2. **Private Sigstore Deployment (Fulcio + Rekor + TUF):** Self-hosted infrastructure inside the cluster.
3. **Public Sigstore Keyless Signing (Fulcio + Rekor + OIDC):** Ephemeral X.509 certificates tied to GitHub Actions OIDC identity.

## Decision
Adopt **Public Sigstore Keyless Signing (Cosign)**:
- Signatures and attestations (SBOM, vulnerability scan, and SLSA provenance) are signed using ephemeral certificates issued by Fulcio.
- Identity is rooted in the GitHub Actions OIDC token (`job_workflow_ref`).
- Public Rekor provides an immutable transparency log of all signing events.
- Kyverno validates the keyless certificate identity and Rekor entry directly at admission.

## Consequences
- **Positive:** Zero long-lived private keys to manage, rotate, or leak.
- **Positive:** Public transparency log provides verifiable non-repudiation.
- **Trade-off:** Admission controller requires egress access to Rekor, Fulcio, and TUF roots. In the event of a public Sigstore outage, fail-closed admission blocks new pods unless break-glass `PolicyException` is activated.
