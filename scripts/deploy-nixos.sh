#!/usr/bin/env bash

# NixOS Configuration Deployment Script
# This script handles deploying NixOS configurations to containers with better error handling

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMEOUT=300  # 5 minutes timeout for builds

# Hostname to IP mapping for direct connection
declare -A HOST_IPS=(
    ["caddy"]="192.168.99.10"
    ["postgresql"]="192.168.99.11"
    ["authentik"]="192.168.99.12"
    ["dns"]="192.168.99.13"
    ["vaultwarden"]="192.168.99.14"
    ["nextcloud"]="192.168.99.15"
    ["guacamole"]="192.168.99.16"
    ["media"]="192.168.99.17"
    ["monitoring"]="192.168.99.18"
    ["mail"]="192.168.99.19"
)

# Default values
HOST=""
DRY_RUN=false
VERBOSE=false
BUILD_TIMEOUT=300

# Help function
show_help() {
    cat << EOF
NixOS Configuration Deployment Script

Usage: $0 [OPTIONS] HOST

OPTIONS:
    -h, --help              Show this help message
    -n, --dry-run           Show what would be deployed without actually deploying
    -v, --verbose           Verbose output
    -t, --timeout SECONDS   Build timeout in seconds (default: 300)
    --build-host HOST       Use a different host for building (if supported)

HOST: The hostname to deploy to (e.g., caddy, postgresql, dns)

EXAMPLES:
    # Deploy to Caddy container
    $0 caddy

    # Dry run to see what would be deployed
    $0 -n caddy

    # Deploy with verbose output and 10 minute timeout
    $0 -v -t 600 caddy

    # Deploy to all Phase 1 containers
    $0 --all-phase1

    # Deploy to all containers
    $0 --all
EOF
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

# Check if host is accessible
check_host_access() {
    local host="$1"
    local ip="${HOST_IPS[$host]}"
    
    if [[ -z "$ip" ]]; then
        log_error "No IP address configured for host: $host"
        return 1
    fi
    
    log_info "Checking SSH access to $host ($ip)..."
    
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$ip" "echo 'SSH test successful'" > /dev/null 2>&1; then
        log_error "Cannot SSH to $host ($ip)"
        return 1
    fi
    
    log_success "SSH access to $host ($ip) confirmed"
    return 0
}

# Copy age key to host for SOPS decryption
copy_age_key() {
    local host="$1"
    local ip="${HOST_IPS[$host]}"
    
    # Check if age key exists locally
    local age_key_path="$HOME/.config/sops/age/keys.txt"
    if [[ ! -f "$age_key_path" ]]; then
        log_warning "Age key not found at $age_key_path - SOPS decryption may fail"
        return 0
    fi
    
    log_info "Copying age key to $host ($ip)..."
    
    # Create age directory and copy key
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$ip" "mkdir -p /etc/age && chmod 700 /etc/age"; then
        if scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$age_key_path" "root@$ip:/etc/age/keys.txt"; then
            if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$ip" "chmod 600 /etc/age/keys.txt"; then
                log_success "Age key copied to $host successfully"
                return 0
            else
                log_error "Failed to set permissions on age key for $host"
                return 1
            fi
        else
            log_error "Failed to copy age key to $host"
            return 1
        fi
    else
        log_error "Failed to create age directory on $host"
        return 1
    fi
}

# Deploy to a single host
deploy_host() {
    local host="$1"
    
    log_info "Deploying NixOS configuration to $host..."
    
    # Check host access
    if ! check_host_access "$host"; then
        return 1
    fi
    
    # Copy age key for SOPS decryption
    if ! copy_age_key "$host"; then
        log_warning "Age key copy failed for $host - continuing with deployment"
    fi
    
    # Check if the flake configuration is valid (syntax check only)
    log_info "Checking flake configuration syntax..."
    if ! nix eval ".#nixosConfigurations.$host.config.system.build.toplevel" > /dev/null 2>&1; then
        log_error "Flake configuration for $host has syntax errors"
        return 1
    fi
    
    # Deploy to remote host
    local ip="${HOST_IPS[$host]}"
    log_info "Deploying to $host ($ip)..."
    
    # Configure SSH options to prevent host key confirmation
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    local deploy_cmd="nixos-rebuild switch --flake .#$host --target-host root@$ip"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would run: $deploy_cmd on $host"
        return 0
    fi
    
    # Use timeout to prevent hanging builds with NIX_SSHOPTS
    if NIX_SSHOPTS="$ssh_opts" timeout "$BUILD_TIMEOUT" nix run nixpkgs#nixos-rebuild -- switch --flake ".#$host" --target-host "root@$ip"; then
        log_success "Successfully deployed to $host"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "Build timed out after ${BUILD_TIMEOUT}s on $host"
            log_warning "This might be due to storage issues. Consider:"
            log_warning "1. Using a different storage pool"
            log_warning "2. Using a different build host"
            log_warning "3. Checking SSD health"
        else
            log_error "Failed to deploy to $host (exit code: $exit_code)"
        fi
        return 1
    fi
}

# Deploy to all Phase 1 containers
deploy_phase1() {
    local hosts=("caddy" "postgresql" "dns")
    local failed_hosts=()
    
    log_info "Deploying to Phase 1 containers: ${hosts[*]}"
    
    for host in "${hosts[@]}"; do
        if deploy_host "$host"; then
            log_success "Phase 1 deployment to $host completed"
        else
            log_error "Phase 1 deployment to $host failed"
            failed_hosts+=("$host")
        fi
        echo  # Add spacing between deployments
    done
    
    if [[ ${#failed_hosts[@]} -eq 0 ]]; then
        log_success "All Phase 1 deployments completed successfully!"
    else
        log_error "Phase 1 deployments failed for: ${failed_hosts[*]}"
        return 1
    fi
}

# Deploy to all containers
deploy_all() {
    local hosts=("caddy" "postgresql" "dns" "authentik" "nextcloud" "media" "monitoring" "guacamole" "vaultwarden" "mail")
    local failed_hosts=()
    
    log_info "Deploying to all containers: ${hosts[*]}"
    
    for host in "${hosts[@]}"; do
        if deploy_host "$host"; then
            log_success "Deployment to $host completed"
        else
            log_error "Deployment to $host failed"
            failed_hosts+=("$host")
        fi
        echo  # Add spacing between deployments
    done
    
    if [[ ${#failed_hosts[@]} -eq 0 ]]; then
        log_success "All deployments completed successfully!"
    else
        log_error "Deployments failed for: ${failed_hosts[*]}"
        return 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--timeout)
            BUILD_TIMEOUT="$2"
            shift 2
            ;;
        --build-host)
            BUILD_HOST="$2"
            shift 2
            ;;
        --all-phase1)
            deploy_phase1
            exit $?
            ;;
        --all)
            deploy_all
            exit $?
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$HOST" ]]; then
                HOST="$1"
            else
                log_error "Multiple hosts specified. Use --all or --all-phase1 for multiple hosts."
                exit 1
            fi
            shift
            ;;
    esac
done

# Main execution
if [[ -z "$HOST" ]]; then
    log_error "No host specified"
    show_help
    exit 1
fi

# Deploy to single host
deploy_host "$HOST"
exit $?
