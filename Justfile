# NixMox Deployment Justfile
# Integrates Terranix, Terraform, and phased deployment

# Global settings
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default environment (override with: just ENV=prod <recipe>)
ENV := "dev"
TERRANIX_FILE := "terranix/" + ENV + ".nix"
TF_DIR := "terraform/environments/" + ENV

# List all recipes
default:
	@just --list

# =============================================================================
# Terranix and Terraform Commands
# =============================================================================

# Render Terranix to Terraform JSON
terranix-render:
	nix run nixpkgs#terranix -- {{TERRANIX_FILE}} > {{TF_DIR}}/main.tf.json
	@echo "Rendered {{TERRANIX_FILE}} -> {{TF_DIR}}/main.tf.json"

# Terraform commands (always render first)
tf-init:
	just terranix-render ENV={{ENV}}
	nix run nixpkgs#terraform -- -chdir={{TF_DIR}} init

tf-plan:
	just terranix-render ENV={{ENV}}
	nix run nixpkgs#terraform -- -chdir={{TF_DIR}} plan

tf-apply:
	just terranix-render ENV={{ENV}}
	nix run nixpkgs#terraform -- -chdir={{TF_DIR}} apply

tf-apply-auto:
	just terranix-render ENV={{ENV}}
	nix run nixpkgs#terraform -- -chdir={{TF_DIR}} apply -auto-approve

tf-destroy:
	just terranix-render ENV={{ENV}}
	nix run nixpkgs#terraform -- -chdir={{TF_DIR}} destroy

# =============================================================================
# Phased Deployment Commands
# =============================================================================

# Deploy Phase 1: Infrastructure Foundation (Proxmox LXC containers)
deploy-phase1 ENV=dev:
	@echo "Deploying Phase 1: Infrastructure Foundation"
	./scripts/deploy-phases.sh -e {{ENV}} -p 1

# Deploy Phase 2: Core Services (NixOS configurations)
deploy-phase2 ENV=dev:
	@echo "Deploying Phase 2: Core Services"
	./scripts/deploy-phases.sh -e {{ENV}} -p 2

# Deploy Phase 3: Application Services
deploy-phase3 ENV=dev:
	@echo "Deploying Phase 3: Application Services"
	./scripts/deploy-phases.sh -e {{ENV}} -p 3

# Deploy Phase 4: Advanced Configuration (Authentik outposts)
deploy-phase4 ENV=dev:
	@echo "Deploying Phase 4: Advanced Configuration"
	./scripts/deploy-phases.sh -e {{ENV}} -p 4

# Deploy to specific phase
deploy-to-phase ENV=dev PHASE=1:
	@echo "Deploying to Phase {{PHASE}}"
	./scripts/deploy-phases.sh -e {{ENV}} -p {{PHASE}}

# Deploy everything
deploy-all ENV=dev:
	@echo "Deploying all phases"
	./scripts/deploy-phases.sh -e {{ENV}} -p 4

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
	nix run nixpkgs#terraform -- apply

# Deploy by tags
colmena-apply-infra:
	@echo "Deploying infrastructure (caddy, postgresql, dns, authentik)"
	nix run nixpkgs#colmena -- apply --on @infra

colmena-apply-core:
	@echo "Deploying core services (caddy, dns, postgresql)"
	nix run nixpkgs#terraform -- apply --on @core

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
	@for host in caddy postgresql authentik nextcloud media monitoring guacamole vaultwarden dns mail; do \
		echo "Testing $$host..."; \
		nix build .#nixosConfigurations.$$host.config.system.build.toplevel >/dev/null 2>&1 && \
		echo "  ✓ $$host" || echo "  ✗ $$host"; \
	done

# Validate flake
validate-flake:
	@echo "Validating flake..."
	nix flake check
	@echo "✓ Flake validation passed"

# Show deployment status
deployment-status ENV=dev:
	@echo "Deployment Status for {{ENV}} environment:"
	@if [ -f "{{TF_DIR}}/terraform.tfstate" ]; then \
		echo "  ✓ Phase 1: Infrastructure containers created"; \
	else \
		echo "  ✗ Phase 1: Infrastructure containers not created"; \
	fi
	@echo "  Next step: just deploy-phase1 ENV={{ENV}}"

# =============================================================================
# Utility Commands
# =============================================================================

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf images/
	rm -rf terraform/environments/*/main.tf.json
	rm -rf terraform/environments/*/.terraform
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
	@echo "Image Building:"
	@echo "  just build-images                    # Build all LXC images"
	@echo "  just build-host caddy               # Build specific host"
	@echo "  just list-hosts                     # List available hosts"
	@echo ""
	@echo "Terraform:"
	@echo "  just tf-plan ENV=dev                # Plan Terraform changes"
	@echo "  just tf-apply ENV=dev               # Apply Terraform changes"
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
	@echo "  just deploy-phase1 ENV=staging      # Deploy Phase 1 to staging"
	@echo "  just build-images -c                # Clean and build all images"
	@echo "  just tf-plan ENV=prod               # Plan production changes"
