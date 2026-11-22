#!/usr/bin/env bash
# Zero-Trust Supply Chain Platform - Bootstrap & Initialization Script
# Architecture: GKE Datapath v2 (Cilium) + Kyverno HA + Falco + Trivy + CNPG + Vault + Loki

set -euo pipefail

echo "==> [1/12] Adding and updating official Helm repositories..."
helm repo add kyverno https://kyverno.github.io/kyverno
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo add jetstack https://charts.jetstack.io
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

echo "==> [2/12] Deploying GCP Infrastructure via Terraform..."
if [ -d "tf" ]; then
  cd tf
  terraform init
  terraform apply -auto-approve
  
  # Connect kubectl to our newly created GKE cluster
  PROJECT_ID=$(terraform output -raw gcp_project_id)
  REGION=$(terraform output -raw gar_location)
  CLUSTER_NAME=$(terraform output -raw gke_cluster_name)
  echo "Connecting to GKE cluster ${CLUSTER_NAME} in ${REGION}..."
  gcloud container clusters get-credentials "${CLUSTER_NAME}" --region "${REGION}" --project "${PROJECT_ID}"
  cd ..
else
  echo "WARN: tf directory not found, skipping terraform apply."
fi

echo "==> [3/13] Creating core application namespaces (Restricted PSA)..."
kubectl apply -f apps/manifests/00-namespace.yaml

echo "==> [4/13] Deploying cert-manager (Internal PKI / Webhooks TLS)..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  -f platform/cert-manager/custom.yaml \
  --wait --timeout 5m

echo "==> [5/13] Deploying Kyverno (HA Admission Controller)..."
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  -f platform/kyverno/custom.yaml \
  --wait --timeout 5m

echo "==> Applying Kyverno Policies & Exceptions..."
kubectl apply -f platform/kyverno/exceptions/
kubectl apply -f platform/kyverno/policies/

echo "==> [6/13] Deploying Falco & Falcosidekick (Modern eBPF Runtime Detection)..."
kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -
# create cm with falco rules
kubectl create configmap falco-zt-rules -n falco \
  --from-file=platform/falco/rules/ \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  -f platform/falco/custom.yaml \
  --wait --timeout 5m

echo "==> [7/13] Deploying Trivy Operator (Continuous Cluster CVE Scanning)..."
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system --create-namespace \
  -f platform/trivy-operator/custom.yaml \
  --wait --timeout 5m

echo "==> [8/13] Deploying CloudNativePG Operator & PostgreSQL HA Cluster..."
helm upgrade --install cnpg-operator cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace \
  -f platform/cnpg/custom.yaml \
  --wait --timeout 5m

echo "==> Creating PostgreSQL database cluster in zt-data ns..."
kubectl apply -f platform/cnpg/cluster.yaml

echo "==> Waiting for PostgreSQL cluster to be ready..."
kubectl wait --for=condition=Ready cluster/postgres -n zt-data --timeout=180s || true

echo "==> [9/13] Deploying HashiCorp Vault HA (Secrets Engine)..."
helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  -f platform/vault/custom.yaml \
  --wait --timeout 5m

echo "==> Initializing and configuring HashiCorp Vault (Dynamic DB Secrets & K8s Auth)..."
./scripts/setup-vault.sh

echo "==> [10/13] Deploying Vault Secrets Operator..."
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vso --create-namespace \
  -f platform/vso/custom.yaml \
  --wait --timeout 5m

echo "==> Applying VSO CRDs (Dynamic Secret Bindings in zt-apps)..."
kubectl apply -f platform/vso/crds/

echo "==> [11/13] Deploying Grafana Loki (Log Aggregation & Audit Trail)..."
helm upgrade --install loki grafana/loki \
  --namespace monitoring --create-namespace \
  -f platform/loki/custom.yaml \
  --wait --timeout 5m

echo "==> [12/13] Enabling Hubble on GKE Datapath v2 (Network Observability)..."
if command -v cilium &> /dev/null; then
  echo "Enabling Hubble Relay and UI via Cilium CLI..."
  cilium hubble enable || true
  cilium hubble enable --ui || true
else
  echo "NOTE: cilium CLI not found. GKE Datapath v2 handles routing. To enable Hubble UI, install cilium CLI or run: cilium hubble enable --ui"
fi

echo "==> [13/13] Applying Cilium Zero-Trust Network Policies (L3/L4/L7 Default-Deny)..."
kubectl apply -f platform/cilium/

echo "==> Deploying Zero-Trust Applications (zt-orders, zt-payments)..."
kubectl apply -f apps/manifests/01-zt-payments.yaml
kubectl apply -f apps/manifests/02-zt-orders.yaml


echo " SUCCESS! Zero-Trust Platform has been successfully initialized on GKE!"
kubectl get pods -A
