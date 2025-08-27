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
    
    # This would use our orchestrator library to generate the plan
    # For now, we'll show the basic structure
    log_info "Deployment phases:"
    log_info "  1. tf:infra - Core infrastructure (postgresql, dns, caddy, authentik)"
    log_info "  2. nix:core - Core NixOS services"
    log_info "  3. tf:auth-core - Authentik resources"
    log_info "  4. Per-service deployment (vaultwarden, guacamole, etc.)"
    
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
    local max_attempts=30
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

# Deploy via SSH using nixos-rebuild
deploy_via_ssh() {
    local service="$1"
    local service_ip="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy $service to $service_ip via remote nixos-rebuild"
        log_info "[DRY-RUN] Would execute: nix run nixpkgs#nixos-rebuild -- switch --flake .#$service --target-host root@$service_ip"
        return 0
    fi
    
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
    if ! terraform plan -out=tfplan; then
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

# Deploy a single service and its dependencies
deploy_single_service() {
    local service="$1"
    
    log_info "Deploying $service and its dependencies..."
    
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
    
    # First, ensure core dependencies are healthy
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
    
    # Now deploy the target service
    log_info "Deploying target service: $service"
    deploy_service "$service"
    
    # Wait for service to be healthy
    wait_for_service_health "$service"
    
    log_success "$service deployment completed"
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
    
    # Generate deployment plan
    generate_plan
    
    # Check if we're deploying a specific service or everything
    if [[ -n "${TARGET_SERVICE:-}" ]]; then
        log_info "Deploying only service: $TARGET_SERVICE"
        deploy_single_service "$TARGET_SERVICE"
    else
        log_info "Deploying all services"
        # Check if infrastructure is already deployed
        if ! check_terraform_state "infra"; then
            log_info "Infrastructure not deployed, running Terraform first..."
            deploy_terraform "infra"
        else
            log_info "Infrastructure already deployed, skipping Terraform phase"
        fi
        
        # Deploy core infrastructure
        deploy_core_infrastructure
        
        # Deploy application services
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
    --service SERVICE   Deploy only the specified service and its dependencies

Examples:
    $0                    # Deploy all services
    $0 --service vaultwarden  # Deploy only vaultwarden and dependencies
    $0 --dry-run         # Show deployment plan without executing

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
        --service)
            TARGET_SERVICE="$2"
            shift 2
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
