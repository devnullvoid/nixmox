#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration
CA_DIR="certs"
CA_NAME="nixmox-internal-ca"
HOSTS=("vaultwarden" "nextcloud" "guacamole" "media" "monitoring" "mail")

# Check if we're in the right directory
if [[ ! -f "flake.nix" ]]; then
    log_error "This script must be run from the nixmox project root directory"
    exit 1
fi

# Function to generate CA certificates
generate_ca() {
    log_info "Generating internal CA certificates..."
    
    if [[ -d "$CA_DIR" && -f "$CA_DIR/$CA_NAME.crt" ]]; then
        log_warning "CA certificates already exist in $CA_DIR/"
        read -p "Regenerate? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Using existing CA certificates"
            return 0
        fi
    fi
    
    # Run the CA generation script
    if [[ -f "scripts/generate-ca.sh" ]]; then
        ./scripts/generate-ca.sh
        log_success "CA certificates generated successfully"
    else
        log_error "CA generation script not found: scripts/generate-ca.sh"
        exit 1
    fi
}

# Function to deploy to a single host
deploy_host() {
    local host="$1"
    
    log_info "Deploying to $host..."
    
    if [[ -f "scripts/deploy-nixos.sh" ]]; then
        if ./scripts/deploy-nixos.sh "$host"; then
            log_success "Successfully deployed to $host"
        else
            log_error "Failed to deploy to $host"
            return 1
        fi
    else
        log_error "Deploy script not found: scripts/deploy-nixos.sh"
        return 1
    fi
}

# Function to deploy to all hosts
deploy_all() {
    log_info "Deploying to all hosts..."
    
    local failed_hosts=()
    
    for host in "${HOSTS[@]}"; do
        if ! deploy_host "$host"; then
            failed_hosts+=("$host")
        fi
    done
    
    if [[ ${#failed_hosts[@]} -eq 0 ]]; then
        log_success "All hosts deployed successfully!"
    else
        log_error "Deployment failed for: ${failed_hosts[*]}"
        exit 1
    fi
}

# Function to deploy to specific hosts
deploy_specific() {
    local hosts=("$@")
    
    log_info "Deploying to specific hosts: ${hosts[*]}"
    
    local failed_hosts=()
    
    for host in "${hosts[@]}"; do
        if ! deploy_host "$host"; then
            failed_hosts+=("$host")
        fi
    done
    
    if [[ ${#failed_hosts[@]} -eq 0 ]]; then
        log_success "All specified hosts deployed successfully!"
    else
        log_error "Deployment failed for: ${failed_hosts[*]}"
        exit 1
    fi
}

# Main script logic
main() {
    log_info "Starting NixMox deployment with internal CA..."
    
    # Generate CA certificates first
    generate_ca
    
    # Check command line arguments
    case "$1" in
        "all")
            deploy_all
            ;;
        "ca-only")
            log_info "CA generation complete. Run 'deploy-with-ca.sh all' to deploy to all hosts."
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  all       - Generate CA and deploy to all hosts"
            echo "  ca-only   - Generate CA certificates only"
            echo "  help      - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 all                    # Deploy to all hosts"
            echo "  $0 ca-only                # Generate CA only"
            echo "  $0 vaultwarden nextcloud  # Deploy to specific hosts"
            echo ""
            echo "Available hosts: ${HOSTS[*]}"
            ;;
        "")
            log_error "No command specified. Use 'help' for usage information."
            exit 1
            ;;
        *)
            # Treat as specific host names
            deploy_specific "$@"
            ;;
    esac
    
    log_success "Deployment completed!"
}

# Run main function with all arguments
main "$@"
