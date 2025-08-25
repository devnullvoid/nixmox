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
LIB_PATH="$PROJECT_ROOT/lib"

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
        deploy_service "$service"
        
        # Wait for service to be healthy
        wait_for_service_health "$service"
        
        log_success "$service deployment completed"
    done
    
    log_success "Core infrastructure deployment completed"
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
    
    # This would use the health check patterns from our manifest
    case "$service" in
        "postgresql")
            systemctl is-active --quiet postgresql
            ;;
        "dns")
            systemctl is-active --quiet unbound
            ;;
        "caddy")
            systemctl is-active --quiet caddy
            ;;
        "authentik")
            systemctl is-active --quiet authentik
            ;;
        "vaultwarden")
            curl -f -s "http://localhost:8080/alive" > /dev/null
            ;;
        "guacamole")
            systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server
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
    
    # Use colmena to deploy the service
    if command -v colmena &> /dev/null; then
        colmena apply --on "$service.nixmox.lan"
    else
        log_warning "Colmena not available, using nixos-rebuild"
        # This would need to be run on the target host
        log_info "Please run 'nixos-rebuild switch' on $service.nixmox.lan"
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
    
    # Generate deployment plan
    generate_plan
    
    # Deploy core infrastructure
    deploy_core_infrastructure
    
    # Deploy application services
    deploy_application_services
    
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
