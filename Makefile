.PHONY: help up down lint test verify redteam compliance vault-setup clean

TF_DIR ?= tf

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Provision GKE infrastructure and bootstrap entire Zero-Trust platform
	@echo "==> Deploying GKE & Zero-Trust stack..."
	@./scripts/cluster-init.sh

down: ## Tear down GCP infrastructure via Terraform
	@echo "==> Destroying GKE cluster and GCP infrastructure..."
	@cd $(TF_DIR) && terraform destroy -auto-approve

vault-setup: ## Configure HashiCorp Vault dynamic database secrets & k8s auth
	@echo "==> Configuring Vault dynamic secrets and policies..."
	@./scripts/setup-vault.sh

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

clean: ## Clean local caches and temporary files
	@echo "==> Cleaning cache directories and temporary files..."
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	@rm -f .vault-init.json
