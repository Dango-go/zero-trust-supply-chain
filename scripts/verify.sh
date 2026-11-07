#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " Zero-Trust Supply Chain: Image Signature & Attestation Check"
echo "=========================================================="

IMAGE_REF="${1:-}"
if [[ -z "${IMAGE_REF}" ]]; then
  echo "Usage: $0 <image-digest-reference>"
  echo "Example: $0 ghcr.io/org/zt-orders@sha256:..."
  exit 1
fi

echo "==> 1. Verifying Cosign Keyless Signature..."
cosign verify "${IMAGE_REF}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

echo "==> 2. Verifying CycloneDX SBOM Attestation..."
cosign verify-attestation --type cyclonedx "${IMAGE_REF}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

echo "==> 3. Verifying Vulnerability Scan Attestation..."
cosign verify-attestation --type vuln "${IMAGE_REF}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

echo "==> 4. Verifying SLSA Build L3 Provenance Attestation..."
cosign verify-attestation --type slsaprovenance "${IMAGE_REF}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

echo "[SUCCESS] All signatures and attestations verified successfully!"
