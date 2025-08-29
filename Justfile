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

# Deploy Phase 1: Infrastructure Foundation (DNS, PostgreSQL, Caddy, Authentik)
deploy-phase1:
	@echo "Deploying Phase 1: Infrastructure Foundation"
	./scripts/deploy-orchestrator.sh --phase 1

# Deploy Phase 2: Authentik Resources (Terraform + outpost tokens)
deploy-phase2:
	@echo "Deploying Phase 2: Authentik Resources (full deployment)"
	./scripts/deploy-orchestrator.sh --phase 2

# Deploy Phase 2: Authentik Resources (Terraform only)
deploy-phase2-tf:
	@echo "Deploying Phase 2: Authentik Resources (Terraform only)"
	./scripts/deploy-orchestrator.sh --phase 2 --terraform-only

# Deploy specific service
deploy-service service:
	@echo "Deploying service: {{service}}"
	./scripts/deploy-orchestrator.sh --service {{service}}

# Deploy everything
deploy-all:
	@echo "Deploying all phases and services"
	./scripts/deploy-orchestrator.sh

# Dry run to see what would be deployed
deploy-dry-run:
	@echo "Dry run - showing what would be deployed"
	./scripts/deploy-orchestrator.sh --dry-run

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
	@echo "  just deploy-phase1                    # Deploy infrastructure"
	@echo "  just deploy-phase2                    # Deploy Authentik resources"

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
	@echo "  just deploy-phase1                    # Deploy infrastructure"
	@echo "  just deploy-phase2                    # Deploy Authentik resources (full)"
	@echo "  just deploy-phase2-tf                 # Deploy Authentik resources (Terraform only)"
	@echo "  just deploy-service caddy             # Deploy specific service"
	@echo "  just deploy-all                       # Deploy everything"
	@echo "  just deploy-dry-run                   # Show deployment plan"
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
	@echo "  just deploy-phase1                    # Deploy infrastructure"
	@echo "  just deploy-phase2-tf                 # Deploy Authentik Terraform only"
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
	@echo "Note: Run 'just deploy-phase2' for full deployment with outpost tokens"

# Quick full deployment
full: infra auth
	@echo "✓ Full deployment completed"
	@echo "Note: Run 'just deploy-all' for complete orchestrator deployment"
