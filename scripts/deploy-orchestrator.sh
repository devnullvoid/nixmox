#!/usr/bin/env bash

# NixMox Orchestrator Deployment Script
# This script uses the orchestrator library to deploy services based on the manifest

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_PATH="$PROJECT_ROOT/nixos/service-manifest.nix"
LIB_PATH="$PROJECT_ROOT"

# Global variables
DRY_RUN=false
TARGET_SERVICE=""
TARGET_PHASE=""
INCREMENTAL_MODE=false
ONLY_SERVICES=""
SKIP_SERVICES=""
FORCE_REDEPLOY=""
TERRAFORM_ONLY=false

# Manifest reading functions
get_service_ip() {
    local service="$1"
    
    # Try to get IP from core_services first, then from services
    local ip=$(nix eval -f "$MANIFEST_PATH" "core_services.$service.ip" --raw 2>/dev/null || \
                nix eval -f "$MANIFEST_PATH" "services.$service.ip" --raw 2>/dev/null)
    
    if [[ -z "$ip" ]]; then
        log_error "Could not find IP address for service: $service"
        return 1
    fi
    
    echo "$ip"
}

get_service_hostname() {
    local service="$1"
    
    # Try to get hostname from core_services first, then from services
    local hostname=$(nix eval -f "$MANIFEST_PATH" "core_services.$service.hostname" --raw 2>/dev/null || \
                     nix eval -f "$MANIFEST_PATH" "services.$service.hostname" --raw 2>/dev/null)
    
    if [[ -z "$hostname" ]]; then
        log_error "Could not find hostname for service: $service"
        return 1
    fi
    
    echo "$hostname"
}

get_service_dependencies() {
    local service="$1"
    
    # Try to get dependencies from services (core_services don't have dependencies)
    local deps=$(nix eval -f "$MANIFEST_PATH" "services.$service.depends_on" --json 2>/dev/null || echo "[]")
    
    echo "$deps"
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v nix &> /dev/null; then
        log_error "Nix is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v colmena &> /dev/null; then
        log_warning "Colmena is not installed. Some features may not work."
    fi
    
    if ! command -v terraform &> /dev/null; then
        log_warning "Terraform is not installed. Terraform phases will be skipped."
    fi
    
    log_success "Prerequisites check completed"
}

# Validate manifest
validate_manifest() {
    log_info "Validating service manifest..."
    
    if ! nix eval -f "$MANIFEST_PATH" --show-trace > /dev/null 2>&1; then
        log_error "Failed to validate manifest syntax"
        exit 1
    fi
    
    log_success "Manifest validation passed"
}

# Generate deployment plan
generate_plan() {
    log_info "Generating deployment plan..."

    # Show the phase structure
    log_info "Deployment phases:"
    log_info "  1. tf:infra + nix:core - Core infrastructure (postgresql, dns, caddy, authentik)"
    log_info "  2. tf:authentik - Authentik resources (outposts, OIDC apps, LDAP/RADIUS apps)"
    log_info "  3. services - Application services (vaultwarden, guacamole, etc.)"

    # Show available deployment modes
    if [[ -n "${TARGET_PHASE:-}" ]]; then
        log_info "Deploying only Phase $TARGET_PHASE"
    elif [[ -n "${TARGET_SERVICE:-}" ]]; then
        log_info "Deploying only service: $TARGET_SERVICE"
    else
        log_info "Full deployment: All phases (1-3)"
    fi

    log_success "Deployment plan generated"
}

# Deploy core infrastructure
deploy_core_infrastructure() {
    log_info "Deploying core infrastructure..."
    
    # Deploy core services in order
    local core_services=("postgresql" "dns" "caddy" "authentik")
    
    for service in "${core_services[@]}"; do
        log_info "Deploying $service..."
        
        # Check if service is already running
        if is_service_healthy "$service"; then
            log_success "$service is already healthy, skipping"
            continue
        fi
        
        # Deploy the service
        deploy_core_service "$service"
        
        # Wait for service to be healthy
        wait_for_service_health "$service"
        
        log_success "$service deployment completed"
    done
    
    log_success "Core infrastructure deployment completed"
}

# Deploy a core service
deploy_core_service() {
    local service="$1"
    
    log_info "Deploying core service: $service"
    
    # Get the IP address for the service from manifest
    local service_ip
    if ! service_ip=$(get_service_ip "$service"); then
        log_error "Failed to get IP address for core service $service"
        return 1
    fi
    
    # Deploy via SSH for core services
    deploy_via_ssh "$service" "$service_ip"
}

# Deploy application services
deploy_application_services() {
    log_info "Deploying application services..."
    
    # Get services from manifest (this would be parsed from the manifest)
    local app_services=("vaultwarden" "guacamole" "monitoring" "nextcloud" "media" "mail")
    
    for service in "${app_services[@]}"; do
        log_info "Deploying $service..."
        
        # Check dependencies
        if ! check_service_dependencies "$service"; then
            log_error "$service dependencies not met, skipping"
            continue
        fi
        
        # Deploy the service
        deploy_service "$service"
        
        # Wait for service to be healthy
        wait_for_service_health "$service"
        
        log_success "$service deployment completed"
    done
    
    log_success "Application services deployment completed"
}

# Check if a service is healthy
is_service_healthy() {
    local service="$1"
    
    # Skip health checks during dry runs
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Skipping health check for $service"
        return 0  # Assume healthy during dry run
    fi
    
    # Get the IP address for the service from manifest
    local service_ip
    if ! service_ip=$(get_service_ip "$service"); then
        log_warning "Unknown service: $service"
        return 1
    fi
    
    # SSH to the target host and run the health check
    case "$service" in
        "postgresql")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet postgresql" 2>/dev/null
            ;;
        "dns")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet unbound" 2>/dev/null
            ;;
        "caddy")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet caddy" 2>/dev/null
            ;;
        "authentik")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet authentik" 2>/dev/null
            ;;
        "vaultwarden")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "curl -f -s http://localhost:8080/alive > /dev/null" 2>/dev/null
            ;;
        "guacamole")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server" 2>/dev/null
            ;;
        "monitoring")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet prometheus && systemctl is-active --quiet grafana" 2>/dev/null
            ;;
        "nextcloud")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet nextcloud" 2>/dev/null
            ;;
        "media")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet transmission" 2>/dev/null
            ;;
        "mail")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$service_ip" "systemctl is-active --quiet postfix && systemctl is-active --quiet dovecot" 2>/dev/null
            ;;
        *)
            log_warning "Unknown service: $service"
            return 1
            ;;
    esac
}

# Wait for a service to be healthy
wait_for_service_health() {
    local service="$1"
    local max_attempts=5
    local attempt=1
    
    # Skip waiting during dry runs
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Skipping health wait for $service"
        return 0
    fi
    
    log_info "Waiting for $service to be healthy..."
    
    while [ $attempt -le $max_attempts ]; do
        if is_service_healthy "$service"; then
            log_success "$service is now healthy"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts: $service not yet healthy, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log_error "$service failed to become healthy after $max_attempts attempts"
    return 1
}

# Check service dependencies
check_service_dependencies() {
    local service="$1"
    
    # This would parse the manifest to check dependencies
    # For now, hardcode the known dependencies
    case "$service" in
        "vaultwarden"|"guacamole"|"monitoring"|"nextcloud"|"media"|"mail")
            # These services depend on core services
            is_service_healthy "postgresql" && \
            is_service_healthy "caddy" && \
            is_service_healthy "authentik"
            ;;
        *)
            return 0
            ;;
    esac
}

# Deploy a single service
deploy_service() {
    local service="$1"
    
    log_info "Deploying $service using NixOS..."
    
    # Get the IP address for the service from manifest
    local service_ip
    if ! service_ip=$(get_service_ip "$service"); then
        log_error "Failed to get IP address for $service"
        return 1
    fi
    
    # Use SSH deployment (Colmena requires a colmena.nix configuration file)
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy $service via SSH to $service_ip"
        return 0
    fi
    
    log_info "Using SSH deployment for $service to $service_ip"
    deploy_via_ssh "$service" "$service_ip"
}

# Check if target host has age key and bootstrap if needed
bootstrap_age_key() {
    local service="$1"
    local service_ip="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would check and bootstrap age key for $service at $service_ip"
        return 0
    fi

    log_info "Checking age key on $service ($service_ip)..."

    # Configure SSH options
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

    # Check if age key exists on target host
    if ssh $ssh_opts "root@$service_ip" "test -f /root/.config/sops/age/keys.txt && test -s /root/.config/sops/age/keys.txt"; then
        log_info "Age key already exists on $service"
        return 0
    fi

    log_info "Age key not found on $service, bootstrapping..."

    # Clean up any existing incorrect age key files
    ssh $ssh_opts "root@$service_ip" "rm -f /etc/age/keys.txt /root/.config/sops/age/keys.txt"

    # Create temporary file for decrypted age key
    local temp_age_file=$(mktemp)

    # Decrypt the full secrets file and extract just the age_key section
    if ! sops decrypt "$PROJECT_ROOT/secrets/default.yaml" | grep -A 10 "age_key:" | grep "AGE-SECRET-KEY" > "$temp_age_file"; then
        log_error "Failed to extract age key from secrets"
        rm -f "$temp_age_file"
        return 1
    fi

    # Check if we got the age key content
    if [[ ! -s "$temp_age_file" ]]; then
        log_error "No age key content extracted"
        rm -f "$temp_age_file"
        return 1
    fi

    # Copy the decrypted age key file to the target host
    if scp $ssh_opts "$temp_age_file" "root@$service_ip:/tmp/age-key-temp" && scp $ssh_opts "$PROJECT_ROOT/.sops.yaml" "root@$service_ip:/etc/.sops.yaml"; then
        # Move files to correct locations and create clean age key file
        if ssh $ssh_opts "root@$service_ip" "mkdir -p /etc/age /root/.config/sops/age && sed 's/^[[:space:]]*//' /tmp/age-key-temp > /etc/age/keys.txt && cp /etc/age/keys.txt /root/.config/sops/age/keys.txt && chmod 400 /etc/age/keys.txt /root/.config/sops/age/keys.txt && chmod 644 /etc/.sops.yaml"; then
            log_success "Age key and SOPS config successfully bootstrapped to $service"
            rm -f "$temp_age_file"
            return 0
        else
            log_error "Failed to move bootstrap files on remote host"
        fi
    else
        log_error "Failed to copy bootstrap files to $service"
    fi

    # Clean up temporary file
    rm -f "$temp_age_file"
    return 1
}

# Deploy via SSH using nixos-rebuild
deploy_via_ssh() {
    local service="$1"
    local service_ip="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy $service to $service_ip via remote nixos-rebuild"
        log_info "[DRY-RUN] Would execute: nix run nixpkgs#nixos-rebuild -- switch --flake .#$service --target-host root@$service_ip"
        return 0
    fi

    # Bootstrap age key if needed
    if ! bootstrap_age_key "$service" "$service_ip"; then
        log_error "Failed to bootstrap age key for $service"
        return 1
    fi

    log_info "Using SSH deployment for $service to $service_ip"
    deploy_via_ssh_unchecked "$service" "$service_ip"
}

# Deploy via SSH using nixos-rebuild (without age key bootstrap)
deploy_via_ssh_unchecked() {
    local service="$1"
    local service_ip="$2"

    log_info "Deploying $service to $service_ip via remote nixos-rebuild..."

    # Use nix run nixpkgs#nixos-rebuild with remote target host
    # This builds locally and deploys remotely without copying the entire flake
    log_info "Building and deploying $service configuration..."

    # Configure SSH options to prevent host key confirmation
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

    if NIX_SSHOPTS="$ssh_opts" nix run nixpkgs#nixos-rebuild -- switch --flake ".#$service" --target-host "root@$service_ip"; then
        log_success "NixOS deployment successful for $service"
    else
        log_error "NixOS deployment failed for $service"
        return 1
    fi
}

# Check if Terraform infrastructure is already deployed
check_terraform_state() {
    local phase="$1"
    
    if ! command -v terraform &> /dev/null; then
        log_warning "Terraform not available, assuming infrastructure not deployed"
        return 1
    fi
    
    # Check if we're in the right directory
    if [[ ! -d "$PROJECT_ROOT/terraform" ]]; then
        log_warning "Terraform directory not found, assuming infrastructure not deployed"
        return 1
    fi
    
    # Change to Terraform directory
    cd "$PROJECT_ROOT/terraform" || {
        log_warning "Failed to change to Terraform directory, assuming infrastructure not deployed"
        return 1
    }
    
    # Check if state file exists
    if [[ ! -f "terraform.tfstate" ]]; then
        log_info "No Terraform state file found, infrastructure not deployed"
        return 1
    fi
    
    # Check if the required resources exist in state
    log_info "Checking Terraform state for existing infrastructure..."
    if terraform state list | grep -q "proxmox_lxc"; then
        log_info "Proxmox LXC containers found in state, infrastructure appears deployed"
        return 0
    else
        log_info "No Proxmox LXC containers found in state, infrastructure not deployed"
        return 1
    fi
}

# Deploy Terraform infrastructure
deploy_terraform() {
    local phase="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute Terraform for phase: $phase"
        log_info "[DRY-RUN] Would run: cd terraform/environments/dev && terraform plan && terraform apply"
        return 0
    fi

    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not available, skipping $phase phase"
        return 1
    fi

    log_info "Executing Terraform for phase: $phase"

    # Change to Terraform directory
    cd "$PROJECT_ROOT/terraform/environments/dev" || {
        log_error "Failed to change to Terraform directory"
        return 1
    }

    # Build Terraform variables
    local tf_vars=""
    if [[ "$INCREMENTAL_MODE" == "true" ]]; then
        tf_vars="$tf_vars -var=\"incremental_mode=true\""
    fi
    if [[ -n "$ONLY_SERVICES" ]]; then
        tf_vars="$tf_vars -var=\"only_services=$ONLY_SERVICES\""
    fi
    if [[ -n "$SKIP_SERVICES" ]]; then
        tf_vars="$tf_vars -var=\"skip_services=$SKIP_SERVICES\""
    fi
    if [[ -n "$FORCE_REDEPLOY" ]]; then
        tf_vars="$tf_vars -var=\"force_redeploy=$FORCE_REDEPLOY\""
    fi

    # Initialize Terraform if needed
    if [[ ! -d ".terraform" ]]; then
        log_info "Initializing Terraform..."
        if ! terraform init; then
            log_error "Terraform initialization failed"
            return 1
        fi
    fi

    # Plan and apply
    log_info "Planning Terraform changes..."
    if ! terraform plan $tf_vars -out=tfplan; then
        log_error "Terraform plan failed"
        return 1
    fi

    log_info "Applying Terraform changes..."
    if ! terraform apply tfplan; then
        log_error "Terraform apply failed"
        return 1
    fi

    # Clean up plan file
    rm -f tfplan

    log_success "Terraform deployment completed for phase: $phase"
}

# Deploy Phase 2: Authentik Resources (tf:authentik)
deploy_phase2_authentik() {
    log_info "Deploying Phase 2: Authentik Resources (tf:authentik)..."

    # Ensure core services are deployed and healthy first
    if ! check_core_services_healthy; then
        log_info "Core services not healthy, deploying core infrastructure first..."
        deploy_core_infrastructure
    fi

    # Check if Phase 2 Terraform resources are already deployed
    if check_phase2_terraform_deployed; then
        log_info "Phase 2 Terraform resources already deployed, skipping Terraform deployment"
    else
        # Deploy Terraform Phase 2 resources
        log_info "Deploying Terraform Phase 2 resources..."
        if ! deploy_terraform_phase2; then
            log_error "Failed to deploy Terraform Phase 2 resources"
            return 1
        fi
    fi

    # Update outpost tokens and secrets
    log_info "Updating outpost tokens and secrets..."
    if ! update_outpost_tokens; then
        log_error "Failed to update outpost tokens"
        return 1
    fi

    # Re-deploy authentik service with updated secrets
    log_info "Re-deploying authentik service with updated outpost tokens..."
    if ! redeploy_authentik_service; then
        log_error "Failed to re-deploy authentik service"
        return 1
    fi

    log_success "Phase 2 (tf:authentik) deployment completed successfully!"
}

# Check if core services are healthy
check_core_services_healthy() {
    local core_services=("postgresql" "dns" "caddy" "authentik")
    local all_healthy=true

    for service in "${core_services[@]}"; do
        if ! is_service_healthy "$service"; then
            log_info "Core service $service is not healthy"
            all_healthy=false
            break
        fi
    done

    $all_healthy
}

# Check if Phase 2 Terraform resources are deployed
check_phase2_terraform_deployed() {
    if ! command -v terraform &> /dev/null; then
        log_warning "Terraform not available, assuming Phase 2 not deployed"
        return 1
    fi

    cd "$PROJECT_ROOT/terraform" || {
        log_warning "Failed to change to Terraform directory"
        return 1
    }

    # Check for Phase 2 resources in Terraform state
    if terraform state list | grep -q "authentik_application.ldap_app\|authentik_application.radius_app"; then
        log_info "Phase 2 resources found in Terraform state"
        return 0
    else
        log_info "Phase 2 resources not found in Terraform state"
        return 1
    fi
}

# Deploy Terraform Phase 2 resources
deploy_terraform_phase2() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy Terraform Phase 2 resources"
        return 0
    fi

    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not available, cannot deploy Phase 2 resources"
        return 1
    fi

    cd "$PROJECT_ROOT/terraform" || {
        log_error "Failed to change to Terraform directory"
        return 1
    }

    # Plan Phase 2 deployment
    log_info "Planning Terraform Phase 2 deployment..."
    if ! terraform plan -var="deployment_phase=2" -var="secrets_file=environments/dev/secrets.sops.yaml"; then
        log_error "Terraform plan failed for Phase 2"
        return 1
    fi

    # Apply Phase 2 deployment
    log_info "Applying Terraform Phase 2 deployment..."
    if ! terraform apply -var="deployment_phase=2" -var="secrets_file=environments/dev/secrets.sops.yaml" --auto-approve; then
        log_error "Terraform apply failed for Phase 2"
        return 1
    fi

    log_success "Terraform Phase 2 deployment completed"
    return 0
}

# Update outpost tokens using the update script
update_outpost_tokens() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update outpost tokens"
        return 0
    fi

    # Get outpost IDs from Terraform output
    local ldap_outpost_id
    local radius_outpost_id

    cd "$PROJECT_ROOT/terraform" || {
        log_error "Failed to change to Terraform directory"
        return 1
    }

    ldap_outpost_id=$(terraform output authentik_ldap_outpost_id 2>/dev/null | tr -d '"' || echo "")
    radius_outpost_id=$(terraform output authentik_radius_outpost_id 2>/dev/null | tr -d '"' || echo "")

    if [[ -z "$ldap_outpost_id" && -z "$radius_outpost_id" ]]; then
        log_error "No outpost IDs found in Terraform output"
        return 1
    fi

    # Get authentik admin token from secrets
    local admin_token
    admin_token=$(sops decrypt "$PROJECT_ROOT/secrets/default.yaml" | grep -A 20 "authentik:" | grep "AUTHENTIK_BOOTSTRAP_TOKEN=" | cut -d'=' -f2 | tr -d '\n' || echo "")

    if [[ -z "$admin_token" ]]; then
        log_error "Could not retrieve authentik admin token from secrets"
        return 1
    fi

    # Build command arguments
    local cmd_args=("-t" "$admin_token")
    [[ -n "$ldap_outpost_id" ]] && cmd_args+=("-l" "$ldap_outpost_id")
    [[ -n "$radius_outpost_id" ]] && cmd_args+=("-r" "$radius_outpost_id")

    # Run the outpost token update script
    log_info "Running outpost token update script..."
    if ! "$PROJECT_ROOT/scripts/authentik/update-outpost-tokens-simple.sh" "${cmd_args[@]}"; then
        log_error "Outpost token update script failed"
        return 1
    fi

    log_success "Outpost tokens updated successfully"
    return 0
}

# Re-deploy authentik service with updated secrets
redeploy_authentik_service() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would re-deploy authentik service"
        return 0
    fi

    log_info "Re-deploying authentik service..."
    # Use unchecked deployment since age key should already be bootstrapped
    local authentik_ip
    if ! authentik_ip=$(get_service_ip "authentik"); then
        log_error "Failed to get authentik IP address"
        return 1
    fi

    if ! deploy_via_ssh_unchecked "authentik" "$authentik_ip"; then
        log_error "Failed to re-deploy authentik service"
        return 1
    fi

    # Wait for authentik to be healthy
    if ! wait_for_service_health "authentik"; then
        log_error "Authentik service failed to become healthy"
        return 1
    fi

    log_success "Authentik service re-deployed successfully"
    return 0
}

# Deploy a single service and its dependencies
deploy_single_service() {
    local service="$1"

    log_info "Deploying $service and its dependencies..."

    # In incremental mode, be smarter about dependencies
    if [[ "$INCREMENTAL_MODE" == "true" ]]; then
        log_info "🔍 Incremental mode: analyzing dependencies for $service"

        # Get service dependencies
        local deps
        deps=$(get_service_dependencies "$service")

        if [[ -n "$deps" && "$deps" != "[]" ]]; then
            log_info "Dependencies for $service: $deps"

            # Check each dependency
            local dep_array
            IFS=',' read -ra dep_array <<< "$deps"

            for dep in "${dep_array[@]}"; do
                # Remove quotes and brackets
                dep=$(echo "$dep" | sed 's/["\[\]]//g')

                if [[ -n "$dep" ]]; then
                    log_info "Checking dependency: $dep"

                    # Check if dependency service is healthy
                    if is_service_healthy "$dep"; then
                        log_info "✅ Dependency $dep is already healthy"
                    else
                        log_info "⚠️  Dependency $dep is not healthy, deploying it first..."

                        # Recursively deploy the dependency
                        if ! deploy_single_service "$dep"; then
                            log_error "Failed to deploy dependency $dep"
                            return 1
                        fi
                    fi
                fi
            done
        else
            log_info "No dependencies found for $service"
        fi
    fi

    # Check if this service requires Terraform infrastructure
    case "$service" in
        "postgresql"|"dns"|"caddy"|"authentik")
            log_info "$service requires infrastructure deployment, checking if already deployed..."
            if ! check_terraform_state "infra"; then
                log_info "Infrastructure not deployed, running Terraform first..."
                deploy_terraform "infra"
            else
                log_info "Infrastructure already deployed, skipping Terraform phase"
            fi
            ;;
    esac

    # In incremental mode, check if core services are needed
    if [[ "$INCREMENTAL_MODE" == "true" ]]; then
        # Only deploy core infrastructure if it's actually needed
        local needs_core=false

        if ! is_service_healthy "postgresql"; then
            log_info "PostgreSQL not healthy, will deploy core infrastructure..."
            needs_core=true
        fi

        if ! is_service_healthy "caddy"; then
            log_info "Caddy not healthy, will deploy core infrastructure..."
            needs_core=true
        fi

        if ! is_service_healthy "authentik"; then
            log_info "Authentik not healthy, will deploy core infrastructure..."
            needs_core=true
        fi

        if [[ "$needs_core" == "true" ]]; then
            log_info "Deploying required core infrastructure..."
            deploy_core_infrastructure
        else
            log_info "Core infrastructure is healthy, skipping core deployment"
        fi
    else
        # Original behavior for non-incremental mode
        if ! is_service_healthy "postgresql"; then
            log_info "PostgreSQL not healthy, deploying core infrastructure first..."
            deploy_core_infrastructure
        fi

        if ! is_service_healthy "caddy"; then
            log_info "Caddy not healthy, deploying core infrastructure first..."
            deploy_core_infrastructure
        fi

        if ! is_service_healthy "authentik"; then
            log_info "Authentik not healthy, deploying core infrastructure first..."
            deploy_core_infrastructure
        fi
    fi

    # Now deploy the target service
    log_info "Deploying target service: $service"
    deploy_service "$service"

    # Wait for service to be healthy
    wait_for_service_health "$service"

    log_success "$service deployment completed"
}

# Show incremental deployment plan
show_incremental_plan() {
    log_info "🔍 Analyzing current deployment state..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would analyze deployment state and show incremental plan"
        return 0
    fi

    # Run terraform plan with incremental mode to see what would be deployed
    if command -v terraform &> /dev/null; then
        log_info "Checking Terraform incremental plan..."
        cd "$PROJECT_ROOT/terraform/environments/dev" || {
            log_warning "Failed to change to Terraform directory"
            return 1
        }

        # Build Terraform variables for incremental mode
        local tf_vars="-var=\"incremental_mode=true\""
        if [[ -n "$ONLY_SERVICES" ]]; then
            tf_vars="$tf_vars -var=\"only_services=$ONLY_SERVICES\""
        fi
        if [[ -n "$SKIP_SERVICES" ]]; then
            tf_vars="$tf_vars -var=\"skip_services=$SKIP_SERVICES\""
        fi
        if [[ -n "$FORCE_REDEPLOY" ]]; then
            tf_vars="$tf_vars -var=\"force_redeploy=$FORCE_REDEPLOY\""
        fi

        if terraform plan $tf_vars; then
            log_success "Incremental deployment plan generated successfully"
        else
            log_warning "Failed to generate incremental deployment plan"
        fi
    else
        log_warning "Terraform not available, cannot show incremental plan"
    fi
}

# Main deployment function
main() {
    log_info "Starting NixMox orchestrator deployment..."

    # Change to project root
    cd "$PROJECT_ROOT"

    # Check prerequisites
    check_prerequisites

    # Validate manifest
    validate_manifest

    # Show incremental deployment plan if enabled
    if [[ "$INCREMENTAL_MODE" == "true" ]]; then
        log_info "🚀 Incremental deployment mode enabled"
        if [[ -n "$ONLY_SERVICES" ]]; then
            log_info "📋 Only deploying services: $ONLY_SERVICES"
        fi
        if [[ -n "$SKIP_SERVICES" ]]; then
            log_info "🚫 Skipping services: $SKIP_SERVICES"
        fi
        if [[ -n "$FORCE_REDEPLOY" ]]; then
            log_info "🔄 Force redeploying services: $FORCE_REDEPLOY"
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            show_incremental_plan
            log_success "Dry run completed - no changes made"
            exit 0
        fi
    fi

    # Generate deployment plan
    generate_plan
    
    # Check deployment mode
    if [[ -n "${TARGET_PHASE:-}" ]]; then
        # Phase-specific deployment
        case "$TARGET_PHASE" in
            "1"|"infra")
                log_info "Deploying Phase 1: Core Infrastructure"
                # Check if infrastructure is already deployed
                if ! check_terraform_state "infra"; then
                    log_info "Infrastructure not deployed, running Terraform first..."
                    deploy_terraform "infra"
                else
                    log_info "Infrastructure already deployed, skipping Terraform phase"
                fi
                # Deploy core infrastructure
                deploy_core_infrastructure
                ;;
            "2"|"authentik"|"auth")
                if [[ "$TERRAFORM_ONLY" == "true" ]]; then
                    log_info "Deploying Phase 2: Authentik Resources (Terraform only)"
                    # Check if Authentik resources are already deployed
                    if ! check_terraform_authentik; then
                        log_info "Authentik resources not deployed, running Terraform first..."
                        deploy_terraform_authentik
                    else
                        log_info "Authentik resources already deployed, skipping Terraform phase"
                    fi
                else
                    log_info "Deploying Phase 2: Authentik Resources (full deployment)"
                    deploy_phase2_authentik
                fi
                ;;
            *)
                log_error "Unknown phase: $TARGET_PHASE"
                log_error "Valid phases: 1/infra, 2/authentik/auth"
                exit 1
                ;;
        esac
    elif [[ -n "${TARGET_SERVICE:-}" ]]; then
        # Service-specific deployment
        log_info "Deploying only service: $TARGET_SERVICE"
        deploy_single_service "$TARGET_SERVICE"
    else
        # Full deployment (all phases)
        log_info "Deploying all phases (1-2) and services"

        # Phase 1: Core Infrastructure
        log_info "Phase 1: Core Infrastructure"
        if ! check_terraform_state "infra"; then
            log_info "Infrastructure not deployed, running Terraform first..."
            deploy_terraform "infra"
        else
            log_info "Infrastructure already deployed, skipping Terraform phase"
        fi
        deploy_core_infrastructure

        # Phase 2: Authentik Resources
        log_info "Phase 2: Authentik Resources"
        deploy_phase2_authentik

        # Phase 3: Application Services
        log_info "Phase 3: Application Services"
        deploy_application_services
    fi
    
    log_success "NixMox orchestrator deployment completed successfully!"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    --dry-run          Show what would be deployed without actually deploying
    --phase PHASE       Deploy only the specified phase (1/infra, 2/authentik/auth)
    --service SERVICE   Deploy only the specified service and its dependencies

Incremental Deployment Options:
    --incremental       Enable incremental deployment mode (only deploy missing/changed components)
    --only SERVICES      Deploy only specific services (comma-separated list)
    --skip SERVICES      Skip specific services (comma-separated list)
    --force SERVICES     Force redeploy specific services (comma-separated list)
    --terraform-only     For Phase 2, run only Terraform without outpost token updates

Examples:
    $0                           # Deploy all phases (1-2) and services
    $0 --phase 1                 # Deploy only Phase 1 (core infrastructure)
    $0 --phase 2                 # Deploy only Phase 2 (authentik resources + outpost tokens)
    $0 --phase 2 --terraform-only # Deploy only Phase 2 Terraform (no outpost tokens)
    $0 --service vaultwarden     # Deploy only vaultwarden and dependencies
    $0 --dry-run                 # Show deployment plan without executing

Incremental Examples:
    $0 --incremental             # Deploy only missing/changed components
    $0 --only openbao            # Deploy only OpenBao service
    $0 --skip monitoring,mail    # Deploy all except monitoring and mail
    $0 --force vaultwarden       # Force redeploy vaultwarden even if unchanged

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --phase)
            TARGET_PHASE="$2"
            shift 2
            ;;
        --service)
            TARGET_SERVICE="$2"
            shift 2
            ;;
        --incremental)
            INCREMENTAL_MODE=true
            shift
            ;;
        --only)
            ONLY_SERVICES="$2"
            shift 2
            ;;
        --skip)
            SKIP_SERVICES="$2"
            shift 2
            ;;
        --force)
            FORCE_REDEPLOY="$2"
            shift 2
            ;;
        --terraform-only)
            TERRAFORM_ONLY=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
