# NixMox Deployment Justfile
# Integrates Terraform and phased deployment

# Global settings
set shell := ["bash", "-euo", "pipefail", "-c"]

# List all recipes
default:
	@just --list

# =============================================================================
# Terraform Commands (using existing Terraform config)
# =============================================================================

# Terraform commands for the main configuration
tf-init env="dev":
	@echo "Initializing Terraform for {{env}} environment..."
	cd terraform && terraform init

tf-plan env="dev":
	@echo "Planning Terraform changes for {{env}} environment..."
	cd terraform && terraform plan -var="environment={{env}}"

tf-apply env="dev":
	@echo "Applying Terraform changes for {{env}} environment..."
	cd terraform && terraform apply -var="environment={{env}}"

tf-apply-auto env="dev":
	@echo "Applying Terraform changes for {{env}} environment (auto-approve)..."
	cd terraform && terraform apply -auto-approve -var="environment={{env}}"

tf-destroy env="dev":
	@echo "Destroying Terraform resources for {{env}} environment..."
	cd terraform && terraform destroy -var="environment={{env}}"

# Terraform commands for phased deployment
tf-init-phases env="dev":
	@echo "Initializing Terraform phases for {{env}} environment..."
	cd terraform/phases && terraform init

tf-plan-phase env="dev" phase="1":
	@echo "Planning Phase {{phase}} for {{env}} environment..."
	cd terraform/phases && terraform plan -var="environment={{env}}" -var="deployment_phase={{phase}}" -var="secrets_file=../environments/{{env}}/secrets.sops.yaml"

tf-apply-phase env="dev" phase="1":
	@echo "Applying Phase {{phase}} for {{env}} environment..."
	cd terraform/phases && terraform apply -var="environment={{env}}" -var="deployment_phase={{phase}}" -var="secrets_file=../environments/{{env}}/secrets.sops.yaml"

tf-apply-phase-auto env="dev" phase="1":
	@echo "Applying Phase {{phase}} for {{env}} environment (auto-approve)..."
	cd terraform/phases && terraform apply -auto-approve -var="environment={{env}}" -var="deployment_phase={{phase}}" -var="secrets_file=../environments/{{env}}/secrets.sops.yaml"

# =============================================================================
# Phased Deployment Commands
# =============================================================================

# Deploy Phase 1: Infrastructure Foundation (DNS, PostgreSQL, Caddy)
deploy-phase1 env="dev":
	@echo "Deploying Phase 1: Infrastructure Foundation"
	./scripts/deploy-phases.sh -e {{env}} -p 1

# Deploy Phase 2: Authentication Foundation (Authentik only)
deploy-phase2 env="dev":
	@echo "Deploying Phase 2: Authentication Foundation (Authentik)"
	./scripts/deploy-phases.sh -e {{env}} -p 2

# Deploy Phase 3: Application Services (all depend on Authentik)
deploy-phase3 env="dev":
	@echo "Deploying Phase 3: Application Services"
	./scripts/deploy-phases.sh -e {{env}} -p 3

# Deploy Phase 4: Advanced Configuration (Authentik outposts)
deploy-phase4 env="dev":
	@echo "Deploying Phase 4: Advanced Configuration"
	./scripts/deploy-phases.sh -e {{env}} -p 4

# Deploy to specific phase
deploy-to-phase phase env="dev":
	@echo "Deploying to Phase {{phase}}"
	./scripts/deploy-phases.sh -e {{env}} -p {{phase}}

# Deploy everything
deploy-all env="dev":
	@echo "Deploying all phases"
	./scripts/deploy-phases.sh -e {{env}} -p 4

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
# Colmena Deployment Commands
# =============================================================================

# Colmena build and apply
colmena-build:
	nix run nixpkgs#colmena -- build

colmena-apply:
	nix run nixpkgs#colmena -- apply

# Deploy by tags
colmena-apply-infra:
	@echo "Deploying infrastructure (caddy, postgresql, dns, authentik)"
	nix run nixpkgs#colmena -- apply --on @infra

colmena-apply-core:
	@echo "Deploying core services (caddy, dns, postgresql)"
	nix run nixpkgs#colmena -- apply --on @core

colmena-apply-auth:
	@echo "Deploying authentication (authentik)"
	nix run nixpkgs#colmena -- apply --on @auth

colmena-apply-database:
	@echo "Deploying database (postgresql)"
	nix run nixpkgs#colmena -- apply --on @database

colmena-apply-services:
	@echo "Deploying application services"
	nix run nixpkgs#colmena -- apply --on @services

# Deploy specific host
colmena-apply-host host:
	nix run nixpkgs#colmena -- apply --on {{host}}

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
deployment-status env="dev":
	@echo "Deployment Status for {{env}} environment:"
	@if [ -f "terraform/phases/terraform.tfstate" ]; then \
		echo "  ✓ Phase 1: Infrastructure containers created"; \
	else \
		echo "  ✗ Phase 1: Infrastructure containers not created"; \
	fi
	@echo "  Next step: just deploy-phase1 env={{env}}"

# =============================================================================
# Utility Commands
# =============================================================================

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf images/
	rm -rf terraform/.terraform
	rm -rf terraform/phases/.terraform
	@echo "✓ Cleaned"

# Show help
show-help:
	@echo "NixMox Deployment Commands:"
	@echo ""
	@echo "Phased Deployment:"
	@echo "  just deploy-phase1 ENV=dev          # Deploy infrastructure"
	@echo "  just deploy-phase2 ENV=dev          # Deploy core services"
	@echo "  just deploy-phase3 ENV=dev          # Deploy applications"
	@echo "  just deploy-phase4 ENV=dev          # Deploy advanced config"
	@echo ""
	@echo "Terraform (Main):"
	@echo "  just tf-init ENV=dev                # Initialize main Terraform"
	@echo "  just tf-plan ENV=dev                # Plan main Terraform changes"
	@echo "  just tf-apply ENV=dev               # Apply main Terraform changes"
	@echo ""
	@echo "Terraform (Phased):"
	@echo "  just tf-init-phases ENV=dev         # Initialize phased Terraform"
	@echo "  just tf-plan-phase ENV=dev PHASE=1 # Plan specific phase"
	@echo "  just tf-apply-phase ENV=dev PHASE=1 # Apply specific phase"
	@echo ""
	@echo "Image Building:"
	@echo "  just build-images                    # Build all LXC images"
	@echo "  just build-host caddy               # Build specific host"
	@echo "  just list-hosts                     # List available hosts"
	@echo ""
	@echo "Colmena:"
	@echo "  just colmena-apply-infra            # Deploy infrastructure"
	@echo "  just colmena-apply-services         # Deploy application services"
	@echo ""
	@echo "Testing:"
	@echo "  just test-configs                   # Test all NixOS configs"
	@echo "  just validate-flake                 # Validate flake"
	@echo ""
	@echo "Examples:"
	@echo "  just deploy-phase1 env=staging      # Deploy Phase 1 to staging"
	@echo "  just build-images                   # Build all images"
	@echo "  just tf-plan-phase env=prod PHASE=2 # Plan Phase 2 for production"

# NixOS Configuration Deployment
deploy-nixos: deploy-nixos-help
    @echo "Use the NixOS deployment script:"
    @echo "  ./scripts/deploy-nixos.sh help"

deploy-nixos-help:
    @echo "NixOS deployment commands:"
    @echo "  ./scripts/deploy-nixos.sh caddy                    # Deploy to Caddy container"
    @echo "  ./scripts/deploy-nixos.sh postgresql               # Deploy to PostgreSQL container"
    @echo "  ./scripts/deploy-nixos.sh dns                      # Deploy to DNS container"
    @echo "  ./scripts/deploy-nixos.sh --all-phase1             # Deploy to all Phase 1 containers"
    @echo "  ./scripts/deploy-nixos.sh --all                    # Deploy to all containers"
    @echo "  ./scripts/deploy-nixos.sh -n caddy                 # Dry run for Caddy"
    @echo "  ./scripts/deploy-nixos.sh -t 600 caddy             # Deploy with 10 min timeout"

# Simplified deployment commands using the new script
deploy-simple: deploy-simple-help
    @echo "Use the simplified deployment script:"
    @echo "  ./scripts/deploy-simple.sh help"

deploy-simple-help:
    @echo "Quick deployment commands:"
    @echo "  ./scripts/deploy-simple.sh status                    # Show deployment status"
    @echo "  ./scripts/deploy-simple.sh -p 1 plan               # Plan Phase 1"
    @echo "  ./scripts/deploy-simple.sh -p 1 deploy             # Deploy Phase 1 (infrastructure)"
    @echo "  ./scripts/deploy-simple.sh -p 2 deploy             # Deploy Phase 2 (services)"
    @echo "  ./scripts/deploy-simple.sh ssh caddy               # SSH to Caddy container"
    @echo "  ./scripts/deploy-simple.sh logs caddy              # Show Caddy logs"

# Legacy deployment commands (keeping for backward compatibility)
