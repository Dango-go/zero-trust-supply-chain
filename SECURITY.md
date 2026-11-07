# Security Policy

## Reporting Security Issues

We take the security of this project very seriously. If you discover a vulnerability or security flaw, please report it responsibly:

- **Do NOT open a public GitHub issue.**
- Submit reports privately via **GitHub Security Advisories** or email `security@example.com` (GPG key available upon request).
- Please include:
  - Clear description of the vulnerability.
  - Proof-of-concept steps to reproduce.
  - Expected vs actual behavior.
  - Potential impact assessment.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

## Security Controls Overview

This repository operates under a **Zero-Trust Software Supply Chain** model:
- All releases are built using **SLSA Build L3** container generators.
- Images are signed keylessly via **Sigstore (Cosign + Fulcio + Rekor)**.
- Cryptographic provenance, SBOM (CycloneDX), and Vulnerability Attestations (`cosign-vuln`) are verified at admission by **Kyverno**.
- Secrets are dynamically issued via **HashiCorp Vault** with zero long-lived credentials in runtime workloads.
- Network traffic is strictly isolated with **Cilium eBPF Default-Deny** and FQDN allowlists.
- Workloads are strictly sandboxed under **Pod Security Standard: Restricted**.
