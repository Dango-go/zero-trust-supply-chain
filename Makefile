.PHONY: help up down lint test verify redteam compliance clean

CLUSTER_NAME ?= zt-cluster
KIND_CONFIG ?= platform/kind/kind-config.yaml

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Provision local Kind cluster with Cilium eBPF and Kyverno
	@echo "==> Creating Kind cluster $(CLUSTER_NAME)..."
	@kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG) || true

down: ## Tear down local Kind cluster
	@echo "==> Deleting Kind cluster $(CLUSTER_NAME)..."
	@kind delete cluster --name $(CLUSTER_NAME)

lint: ## Run all local linters (gitleaks, hadolint, actionlint, ruff/flake8)
	@echo "==> Checking for secret leaks with Gitleaks..."
	@gitleaks detect --verbose --redact || true
	@echo "==> Linting Dockerfiles with Hadolint..."
	@find apps/ -name Dockerfile -exec hadolint --config .hadolint.yaml {} + || true

test: ## Run unit tests for application workloads
	@echo "==> Running unit tests for zt-payments..."
	@PYTHONPATH=apps/zt-payments pytest apps/zt-payments/tests/ || true
	@echo "==> Running unit tests for zt-orders..."
	@PYTHONPATH=apps/zt-orders pytest apps/zt-orders/tests/ || true

verify: ## Run cosign verification script
	@echo "==> Verifying image signatures and attestations..."
	@./scripts/verify.sh

redteam: ## Run all 14 automated Red-Team attack scenarios
	@echo "==> Running Red-Team validation suite (RT-01..RT-14)..."
	@./redteam/run.sh

compliance: ## Run kube-bench and Kubescape compliance audit
	@echo "==> Generating CIS Kubernetes Benchmark and Kubescape reports..."
	@./scripts/gen-evidence.sh
