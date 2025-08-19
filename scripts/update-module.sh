#!/usr/bin/env bash

set -euo pipefail

# Usage function
usage() {
    cat << EOF
Usage: $0 <module> [options]

Update an existing NixMox module with Terraform changes and secret updates.

Arguments:
    module          The module to update (e.g., authentik, caddy, monitoring)

Options:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be done without executing
    -t, --target-host   Override target host (default: from terraform)
    -v, --verbose       Enable verbose output
    --terraform-only     Only run terraform deployment (skip NixOS deployment)
    --nixos-only        Only run NixOS deployment (skip terraform)

Environment variables:
    BUILD_HOST          Build host for NixOS deployment (default: localhost)
    MAX_JOBS            Maximum build jobs (default: 1)

Examples:
    $0 authentik                    # Full update workflow
    $0 authentik --dry-run         # Show what would be done
    $0 authentik --terraform-only  # Only run terraform
    $0 authentik --nixos-only      # Only run NixOS deployment

Workflow:
    1. Run Terraform plans for module
    2. Run secret update scripts for module
    3. Nix deploy again to update secrets
EOF
}

# Configuration
MODULE=""
DRY_RUN=false
TARGET_HOST=""
VERBOSE=false
TERRAFORM_ONLY=false
NIXOS_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -t|--target-host)
            TARGET_HOST="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --terraform-only)
            TERRAFORM_ONLY=true
            shift
            ;;
        --nixos-only)
            NIXOS_ONLY=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -z "$MODULE" ]]; then
                MODULE="$1"
            else
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required arguments
if [[ -z "$MODULE" ]]; then
    echo "Error: Module is required" >&2
    usage >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

dry_run_log() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] $1${NC}"
    else
        log "$1"
    fi
}

# Check if we're in the right directory
if [[ ! -f "flake.nix" ]]; then
    error "flake.nix not found. Please run this script from the nixmox directory."
    exit 1
fi

# Check if module exists
if [[ ! -d "modules/$MODULE" ]]; then
    error "Module '$MODULE' not found in modules/"
    exit 1
fi

# Check if terraform configuration exists
if [[ ! -d "terraform/$MODULE" ]]; then
    error "Terraform configuration for '$MODULE' not found in terraform/"
    exit 1
fi

# Function to get target host from terraform state or config
get_target_host() {
    if [[ -n "$TARGET_HOST" ]]; then
        echo "$TARGET_HOST"
        return
    fi
    
    # Try to get from terraform state
    if [[ -f "terraform/$MODULE/terraform.tfstate" ]]; then
        # Extract IP from state if available
        local ip=$(cd "terraform/$MODULE" && terraform show -json 2>/dev/null | jq -r '.values.outputs.public_ip // .values.outputs.private_ip // .values.outputs.ip // empty' 2>/dev/null || echo "")
        if [[ -n "$ip" && "$ip" != "null" ]]; then
            echo "root@$ip"
            return
        fi
    fi
    
    # Try to get from terraform.tfvars
    if [[ -f "terraform/$MODULE/terraform.tfvars" ]]; then
        local ip=$(grep -E '^(ip|host|address)' "terraform/$MODULE/terraform.tfvars" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "")
        if [[ -n "$ip" ]]; then
            echo "root@$ip"
            return
        fi
    fi
    
    # Default fallback
    echo "root@192.168.88.194"
}

# Function to deploy NixOS configuration
deploy_nixos() {
    local target_host="$1"
    local step="$2"
    
    log "Step $step: Deploying NixOS configuration for '$MODULE' to $target_host"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_log "Would deploy NixOS configuration for '$MODULE' to $target_host"
        return 0
    fi
    
    # Use the appropriate deployment script
    if [[ -f "scripts/deploy-$MODULE.sh" ]]; then
        log "Using module-specific deployment script: scripts/deploy-$MODULE.sh"
        if ./scripts/deploy-"$MODULE".sh "$MODULE" "$target_host"; then
            success "NixOS deployment completed successfully"
            return 0
        else
            error "NixOS deployment failed"
            return 1
        fi
    elif [[ -f "scripts/deploy.sh" ]]; then
        log "Using generic deployment script: scripts/deploy.sh"
        if ./scripts/deploy.sh "$MODULE" "$target_host"; then
            success "NixOS deployment completed successfully"
            return 0
        else
            error "NixOS deployment failed"
            return 1
        fi
    else
        error "No deployment script found for '$MODULE'"
        return 1
    fi
}

# Function to run Terraform deployment
run_terraform() {
    local target_host="$1"
    
    log "Step 1: Running Terraform deployment for '$MODULE'"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_log "Would run Terraform deployment for '$MODULE'"
        return 0
    fi
    
    cd "terraform/$MODULE"
    
    # Initialize if needed
    if [[ ! -d ".terraform" ]]; then
        log "Initializing Terraform for '$MODULE'..."
        terraform init
    fi
    
    # Plan and apply
    log "Planning Terraform deployment..."
    if terraform plan -out=deploy-plan.tfplan; then
        log "Applying Terraform deployment..."
        if terraform apply deploy-plan.tfplan; then
            success "Terraform deployment completed successfully"
            cd ../..
            return 0
        else
            error "Terraform deployment failed"
            cd ../..
            return 1
        fi
    else
        error "Terraform planning failed"
        cd ../..
        return 1
    fi
}

# Function to run secret update scripts
update_secrets() {
    local target_host="$1"
    
    log "Step 2: Running secret update scripts for '$MODULE'"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_log "Would run secret update scripts for '$MODULE'"
        return 0
    fi
    
    # Check for module-specific update scripts
    local update_script=""
    case "$MODULE" in
        authentik)
            # Check for LDAP and RADIUS outpost scripts
            if [[ -f "scripts/authentik/update-ldap-token.sh" ]] && [[ -f "scripts/authentik/update-radius-token.sh" ]]; then
                log "Running LDAP outpost token update..."
                if ./scripts/authentik/update-ldap-token.sh; then
                    success "LDAP outpost token updated successfully"
                else
                    warn "LDAP outpost token update failed"
                fi
                
                log "Running RADIUS outpost token update..."
                if ./scripts/authentik/update-radius-token.sh; then
                    success "RADIUS outpost token updated successfully"
                else
                    warn "RADIUS outpost token update failed"
                fi
                
                return 0
            fi
            ;;
        *)
            # Look for generic update script
            if [[ -f "scripts/$MODULE/update-secrets.sh" ]]; then
                update_script="scripts/$MODULE/update-secrets.sh"
            elif [[ -f "scripts/update-$MODULE-secrets.sh" ]]; then
                update_script="scripts/update-$MODULE-secrets.sh"
            fi
            
            if [[ -n "$update_script" ]]; then
                log "Running secret update script: $update_script"
                if ./"$update_script"; then
                    success "Secrets updated successfully"
                    return 0
                else
                    error "Secret update failed"
                    return 1
                fi
            else
                warn "No secret update script found for '$MODULE'"
                return 0
            fi
            ;;
    esac
}

# Main update function
main() {
    log "Starting module update for: $MODULE"
    
    # Get target host
    local target_host=$(get_target_host)
    log "Target host: $target_host"
    
    # Step 1: Terraform deployment
    if [[ "$NIXOS_ONLY" == "false" ]]; then
        if ! run_terraform "$target_host"; then
            error "Terraform deployment failed. Exiting."
            exit 1
        fi
    else
        log "Skipping Terraform deployment (nixos-only mode)"
    fi
    
    # Step 2: Update secrets
    if ! update_secrets "$target_host"; then
        warn "Secret update had issues, but continuing..."
    fi
    
    # Step 3: Final NixOS deployment to apply secrets
    if [[ "$TERRAFORM_ONLY" == "false" ]]; then
        log "Step 3: Final NixOS deployment to apply updated secrets"
        if ! deploy_nixos "$target_host" "3"; then
            error "Final NixOS deployment failed. Exiting."
            exit 1
        fi
    else
        log "Skipping final NixOS deployment (terraform-only mode)"
    fi
    
    success "Module update completed successfully for '$MODULE'!"
    log "Module '$MODULE' has been updated with new configuration and secrets"
}

# Run main function
main "$@"
