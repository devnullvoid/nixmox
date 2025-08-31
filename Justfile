# NixMox Deployment Justfile
# Integrates Terraform and orchestrator deployment

# Global settings
set shell := ["bash", "-euo", "pipefail", "-c"]

# List all recipes
default:
	@just --list

# =============================================================================
# Terraform Commands (New Separated Structure)
# =============================================================================

# Infrastructure Terraform commands
tf-infra-init:
	@echo "Initializing Terraform infrastructure..."
	cd terraform/infrastructure && terraform init

tf-infra-plan:
	@echo "Planning Terraform infrastructure changes..."
	cd terraform/infrastructure && terraform plan -var="secrets_file=../secrets/default.yaml"

tf-infra-apply:
	@echo "Applying Terraform infrastructure changes..."
	cd terraform/infrastructure && terraform apply -var="secrets_file=../secrets/default.yaml"

tf-infra-apply-auto:
	@echo "Applying Terraform infrastructure changes (auto-approve)..."
	cd terraform/infrastructure && terraform apply -auto-approve -var="secrets_file=../secrets/default.yaml"

tf-infra-destroy:
	@echo "Destroying Terraform infrastructure..."
	cd terraform/infrastructure && terraform destroy -var="secrets_file=../secrets/default.yaml"

# Authentik Terraform commands
tf-auth-init:
	@echo "Initializing Terraform Authentik..."
	cd terraform/authentik && terraform init

tf-auth-plan:
	@echo "Planning Terraform Authentik changes..."
	cd terraform/authentik && terraform plan -var="secrets_file=../secrets/default.yaml"

tf-auth-apply:
	@echo "Applying Terraform Authentik changes..."
	cd terraform/authentik && terraform apply -var="secrets_file=../secrets/default.yaml"

tf-auth-apply-auto:
	@echo "Applying Terraform Authentik changes (auto-approve)..."
	cd terraform/authentik && terraform apply -auto-approve -var="secrets_file=../secrets/default.yaml"

tf-auth-destroy:
	@echo "Destroying Terraform Authentik resources..."
	cd terraform/authentik && terraform destroy -var="secrets_file=../secrets/default.yaml"

# =============================================================================
# Orchestrator Deployment Commands
# =============================================================================

# Deploy all phases (1-4) with simple Authentik mode (default)
deploy-all:
	@echo "Deploying all phases (1-4) with simple Authentik mode"
	./scripts/deploy-orchestrator.sh

# Deploy all phases (1-4) with full Authentik mode (includes outpost token updates)
deploy-all-full:
	@echo "Deploying all phases (1-4) with full Authentik mode"
	./scripts/deploy-orchestrator.sh --authentik-mode full

# Deploy only Terraform infrastructure (Phase 1)
deploy-infra:
	@echo "Deploying Terraform infrastructure only"
	./scripts/deploy-orchestrator.sh --skip-nixos

# Deploy only NixOS services (Phases 2-4, skipping Terraform)
deploy-nixos:
	@echo "Deploying NixOS services only (skipping Terraform)"
	./scripts/deploy-orchestrator.sh --skip-terraform

# Deploy specific service
deploy-service service:
	@echo "Deploying service: {{service}}"
	./scripts/deploy-orchestrator.sh --service {{service}}

# Dry run to see what would be deployed
deploy-dry-run:
	@echo "Dry run - showing what would be deployed"
	./scripts/deploy-orchestrator.sh --dry-run

# Deploy with custom secrets file
deploy-with-secrets secrets_file:
	@echo "Deploying with custom secrets file: {{secrets_file}}"
	./scripts/deploy-orchestrator.sh --secrets-file {{secrets_file}}

# Deploy with custom secrets file and full Authentik mode
deploy-with-secrets-full secrets_file:
	@echo "Deploying with custom secrets file: {{secrets_file}} and full Authentik mode"
	./scripts/deploy-orchestrator.sh --secrets-file {{secrets_file}} --authentik-mode full

# =============================================================================
# NixOS Image Building
# =============================================================================

# Build NixOS LXC images
build-images:
	./scripts/build-images.sh

# Build specific host image
build-host host:
	./scripts/build-images.sh {{host}}

# Build all host images
build-all-images:
	./scripts/build-images.sh -a

# List available hosts
list-hosts:
	./scripts/build-images.sh -l

# =============================================================================
# Development and Testing
# =============================================================================

# Test NixOS configurations
test-configs:
	@echo "Testing all NixOS configurations..."
	./scripts/deploy-test.sh caddy
	./scripts/deploy-test.sh postgresql  
	./scripts/deploy-test.sh authentik
	./scripts/deploy-test.sh nextcloud
	./scripts/deploy-test.sh media
	./scripts/deploy-test.sh monitoring
	./scripts/deploy-test.sh guacamole
	./scripts/deploy-test.sh vaultwarden
	./scripts/deploy-test.sh dns
	./scripts/deploy-test.sh mail

# Validate flake
validate-flake:
	@echo "Validating flake..."
	nix flake check
	@echo "✓ Flake validation passed"

# Show deployment status
deployment-status:
	@echo "Deployment Status:"
	@if [ -f "terraform/infrastructure/terraform.tfstate" ]; then \
		echo "  ✓ Infrastructure: Terraform state exists"; \
	else \
		echo "  ✗ Infrastructure: No Terraform state"; \
	fi
	@if [ -f "terraform/authentik/terraform.tfstate" ]; then \
		echo "  ✓ Authentik: Terraform state exists"; \
	else \
		echo "  ✗ Authentik: No Terraform state"; \
	fi
	@echo ""
	@echo "Next steps:"
	@echo "  just deploy-all                       # Deploy everything (simple Authentik mode)"
	@echo "  just deploy-all-full                  # Deploy everything (full Authentik mode)"
	@echo "  just deploy-infra                     # Deploy infrastructure only"
	@echo "  just deploy-nixos                     # Deploy NixOS services only"

# =============================================================================
# Utility Commands
# =============================================================================

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf images/
	rm -rf terraform/infrastructure/.terraform
	rm -rf terraform/authentik/.terraform
	rm -rf terraform/infrastructure/*.tfplan
	rm -rf terraform/authentik/*.tfplan
	@echo "✓ Cleaned"

# Show help
show-help:
	@echo "NixMox Deployment Commands:"
	@echo ""
	@echo "Orchestrator Deployment:"
	@echo "  just deploy-all                       # Deploy all phases (1-4) with simple Authentik mode"
	@echo "  just deploy-all-full                  # Deploy all phases (1-4) with full Authentik mode"
	@echo "  just deploy-infra                     # Deploy Terraform infrastructure only"
	@echo "  just deploy-nixos                     # Deploy NixOS services only (skip Terraform)"
	@echo "  just deploy-service caddy             # Deploy specific service"
	@echo "  just deploy-dry-run                   # Show deployment plan"
	@echo "  just deploy-with-secrets file.yaml    # Deploy with custom secrets file"
	@echo "  just deploy-with-secrets-full file.yaml # Deploy with custom secrets and full Authentik mode"
	@echo ""
	@echo "Terraform Infrastructure:"
	@echo "  just tf-infra-init                    # Initialize infrastructure Terraform"
	@echo "  just tf-infra-plan                    # Plan infrastructure changes"
	@echo "  just tf-infra-apply                   # Apply infrastructure changes"
	@echo "  just tf-infra-apply-auto              # Apply infrastructure (auto-approve)"
	@echo ""
	@echo "Terraform Authentik:"
	@echo "  just tf-auth-init                     # Initialize Authentik Terraform"
	@echo "  just tf-auth-plan                     # Plan Authentik changes"
	@echo "  just tf-auth-apply                    # Apply Authentik changes"
	@echo "  just tf-auth-apply-auto               # Apply Authentik (auto-approve)"
	@echo ""
	@echo "Image Building:"
	@echo "  just build-images                     # Build all LXC images"
	@echo "  just build-host caddy                 # Build specific host"
	@echo "  just list-hosts                       # List available hosts"
	@echo ""
	@echo "Testing:"
	@echo "  just test-configs                     # Test all NixOS configs"
	@echo "  just validate-flake                   # Validate flake"
	@echo "  just deployment-status                # Show deployment status"
	@echo ""
	@echo "Examples:"
	@echo "  just deploy-all                       # Deploy everything with simple Authentik mode"
	@echo "  just deploy-all-full                  # Deploy everything with full Authentik mode"
	@echo "  just deploy-infra                     # Deploy infrastructure only"
	@echo "  just deploy-nixos                     # Deploy NixOS services only"
	@echo "  just deploy-service vaultwarden       # Deploy specific service"
	@echo "  just tf-infra-plan                    # Plan infrastructure changes"
	@echo "  just tf-auth-apply-auto               # Apply Authentik changes automatically"

# =============================================================================
# Quick Commands (Common Workflows)
# =============================================================================

# Quick infrastructure deployment
infra: tf-infra-init tf-infra-plan tf-infra-apply-auto
	@echo "✓ Infrastructure deployment completed"

# Quick Authentik deployment (Terraform only)
auth-tf: tf-auth-init tf-auth-plan tf-auth-apply-auto
	@echo "✓ Authentik Terraform deployment completed"

# Quick Authentik deployment (full)
auth: tf-auth-init tf-auth-plan tf-auth-apply-auto
	@echo "✓ Authentik Terraform deployment completed"
	@echo "Note: Run 'just deploy-all-full' for complete deployment with outpost tokens"

# Quick full deployment
full: infra auth
	@echo "✓ Full deployment completed"
	@echo "Note: Run 'just deploy-all' for complete orchestrator deployment"

# Quick orchestrator deployment (simple mode)
deploy: deploy-all
	@echo "✓ Quick orchestrator deployment completed (simple Authentik mode)"

# Quick orchestrator deployment (full mode)
deploy-full: deploy-all-full
	@echo "✓ Quick orchestrator deployment completed (full Authentik mode)"
