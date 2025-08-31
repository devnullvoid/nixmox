#!/usr/bin/env bash

# NixMox Streamlined Deployment Orchestrator
# This script handles the four core deployment steps:
# 1. Terraform infrastructure
# 2. NixOS Core Services
# 3. Terraform Authentik Applications
# 4. Additional NixOS services as needed

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
INFRASTRUCTURE_DIR="$PROJECT_ROOT/terraform/infrastructure"
AUTHENTIK_DIR="$PROJECT_ROOT/terraform/authentik"

# Global variables
DRY_RUN=false
TARGET_SERVICE=""
SKIP_TERRAFORM=false
SKIP_NIXOS=false
AUTHENTIK_MODE="simple"  # "simple" or "full"
SECRETS_FILE="$PROJECT_ROOT/secrets/default.yaml"

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
    
    if ! command -v terraform &> /dev/null; then
        log_warning "Terraform is not installed. Terraform phases will be skipped."
        SKIP_TERRAFORM=true
    fi
    
    if ! command -v sops &> /dev/null; then
        log_warning "SOPS is not installed. Secret management may not work properly."
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some manifest parsing may not work properly."
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

# Get service IP from manifest
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

# Get service hostname from manifest
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

# Bootstrap age key on target host
bootstrap_age_key() {
    local service="$1"
    local service_ip="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would bootstrap age key for $service at $service_ip"
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
    if ! sops decrypt "$SECRETS_FILE" | grep -A 10 "age_key:" | grep "AGE-SECRET-KEY" > "$temp_age_file"; then
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

# Deploy service via SSH using nixos-rebuild
deploy_service_via_ssh() {
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

    log_info "Deploying $service to $service_ip via remote nixos-rebuild..."

    # Configure SSH options to prevent host key confirmation
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

    if NIX_SSHOPTS="$ssh_opts" nix run nixpkgs#nixos-rebuild -- switch --flake ".#$service" --target-host "root@$service_ip"; then
        log_success "NixOS deployment successful for $service"
    else
        log_error "NixOS deployment failed for $service"
        return 1
    fi
}

# Step 1: Deploy Terraform infrastructure
deploy_terraform_infrastructure() {
    if [[ "$SKIP_TERRAFORM" == "true" ]]; then
        log_warning "Skipping Terraform infrastructure deployment"
        return 0
    fi

    log_info "Step 1: Deploying Terraform infrastructure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy Terraform infrastructure from $INFRASTRUCTURE_DIR"
        return 0
    fi

    cd "$INFRASTRUCTURE_DIR" || {
        log_error "Failed to change to infrastructure Terraform directory"
        return 1
    }

    # Initialize Terraform if needed
    if [[ ! -d ".terraform" ]]; then
        log_info "Initializing Terraform infrastructure..."
        if ! terraform init; then
            log_error "Terraform infrastructure initialization failed"
            return 1
        fi
    fi

    # Plan and apply infrastructure
    log_info "Planning Terraform infrastructure changes..."
    if ! terraform plan -var="secrets_file=$SECRETS_FILE" -out=tfplan; then
        log_error "Terraform infrastructure plan failed"
        return 1
    fi

    log_info "Applying Terraform infrastructure changes..."
    if ! terraform apply tfplan; then
        log_error "Terraform infrastructure apply failed"
        return 1
    fi

    # Clean up plan file
    rm -f tfplan

    log_success "Terraform infrastructure deployment completed"
}

# Step 2: Deploy NixOS Core Services
deploy_nixos_core_services() {
    if [[ "$SKIP_NIXOS" == "true" ]]; then
        log_warning "Skipping NixOS core services deployment"
        return 0
    fi

    log_info "Step 2: Deploying NixOS Core Services..."

    # Core services in deployment order
    local core_services=("postgresql" "dns" "caddy" "authentik")
    
    for service in "${core_services[@]}"; do
        log_info "Deploying core service: $service"
        
        # Get service IP from manifest
        local service_ip
        if ! service_ip=$(get_service_ip "$service"); then
            log_error "Failed to get IP address for core service $service"
            return 1
        fi
        
        # Deploy the service
        if ! deploy_service_via_ssh "$service" "$service_ip"; then
            log_error "Failed to deploy core service $service"
            return 1
        fi
        
        log_success "Core service $service deployment completed"
    done
    
    log_success "NixOS Core Services deployment completed"
}

# Step 3: Deploy Terraform Authentik Applications
deploy_terraform_authentik() {
    if [[ "$SKIP_TERRAFORM" == "true" ]]; then
        log_warning "Skipping Terraform Authentik applications deployment"
        return 0
    fi

    log_info "Step 3: Deploying Terraform Authentik Applications..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy Terraform Authentik applications from $AUTHENTIK_DIR"
        if [[ "$AUTHENTIK_MODE" == "full" ]]; then
            log_info "[DRY-RUN] Would also update outpost tokens and re-deploy authentik"
        fi
        return 0
    fi

    cd "$AUTHENTIK_DIR" || {
        log_error "Failed to change to Authentik Terraform directory"
        return 1
    }

    # Initialize Terraform if needed
    if [[ ! -d ".terraform" ]]; then
        log_info "Initializing Terraform Authentik..."
        if ! terraform init; then
            log_error "Terraform Authentik initialization failed"
            return 1
        fi
    fi

    # Deploy Authentik resources
    log_info "Deploying Authentik applications and outposts..."
    if ! terraform apply -var="secrets_file=$SECRETS_FILE" --auto-approve; then
        log_error "Terraform Authentik deployment failed"
        return 1
    fi

    log_success "Terraform Authentik Applications deployment completed"

    # If this is a full deployment, handle outpost tokens and re-deploy authentik
    if [[ "$AUTHENTIK_MODE" == "full" ]]; then
        log_info "Full Authentik mode: Updating outpost tokens and re-deploying authentik..."
        
        if ! update_outpost_tokens_and_redeploy; then
            log_error "Failed to update outpost tokens and re-deploy authentik"
            return 1
        fi
    fi
}

# Update outpost tokens and re-deploy authentik (full mode only)
update_outpost_tokens_and_redeploy() {
    log_info "Updating outpost tokens and re-deploying authentik..."

    # Get outpost IDs from Terraform output
    local ldap_outpost_id
    local radius_outpost_id

    cd "$AUTHENTIK_DIR" || {
        log_error "Failed to change to Authentik Terraform directory"
        return 1
    }

    ldap_outpost_id=$(terraform output -raw authentik_ldap_outpost_id 2>/dev/null || echo "")
    radius_outpost_id=$(terraform output -raw authentik_radius_outpost_id 2>/dev/null || echo "")

    if [[ -z "$ldap_outpost_id" && -z "$radius_outpost_id" ]]; then
        log_error "No outpost IDs found in Terraform output"
        return 1
    fi

    # Get authentik admin token from secrets
    local admin_token
    admin_token=$(sops decrypt "$SECRETS_FILE" | grep -A 20 "authentik:" | grep "AUTHENTIK_BOOTSTRAP_TOKEN=" | cut -d'=' -f2 | tr -d '\n' || echo "")

    if [[ -z "$admin_token" ]]; then
        log_error "Could not retrieve authentik admin token from secrets"
        return 1
    fi

    # Build command arguments for the outpost token update script
    local cmd_args=("-t" "$admin_token" "-s" "$SECRETS_FILE")
    [[ -n "$ldap_outpost_id" ]] && cmd_args+=("-l" "$ldap_outpost_id")
    [[ -n "$radius_outpost_id" ]] && cmd_args+=("-r" "$radius_outpost_id")

    # Run the outpost token update script
    log_info "Running outpost token update script..."
    if ! "$PROJECT_ROOT/scripts/authentik/update-outpost-tokens-simple.sh" "${cmd_args[@]}"; then
        log_error "Outpost token update script failed"
        return 1
    fi

    log_success "Outpost tokens updated successfully"

    # Re-deploy authentik service with updated secrets
    log_info "Re-deploying authentik service with updated outpost tokens..."
    local authentik_ip
    if ! authentik_ip=$(get_service_ip "authentik"); then
        log_error "Failed to get authentik IP address"
        return 1
    fi

    if ! deploy_service_via_ssh "authentik" "$authentik_ip"; then
        log_error "Failed to re-deploy authentik service"
        return 1
    fi

    log_success "Authentik service re-deployed successfully with updated tokens"
    return 0
}

# Step 4: Deploy Additional NixOS Services
deploy_additional_nixos_services() {
    if [[ "$SKIP_NIXOS" == "true" ]]; then
        log_warning "Skipping additional NixOS services deployment"
        return 0
    fi

    log_info "Step 4: Deploying Additional NixOS Services..."

    # Get application services from manifest
    local app_services=$(nix eval -f "$MANIFEST_PATH" "builtins.attrNames services" --json 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
    
    if [[ -z "$app_services" ]]; then
        log_info "No additional services found in manifest"
        return 0
    fi

    # Deploy each application service
    for service in $app_services; do
        log_info "Deploying application service: $service"
        
        # Get service IP from manifest
        local service_ip
        if ! service_ip=$(get_service_ip "$service"); then
            log_error "Failed to get IP address for service $service"
            continue
        fi
        
        # Deploy the service
        if ! deploy_service_via_ssh "$service" "$service_ip"; then
            log_error "Failed to deploy service $service"
            continue
        fi
        
        log_success "Service $service deployment completed"
    done
    
    log_success "Additional NixOS Services deployment completed"
}

# Deploy a single service
deploy_single_service() {
    local service="$1"
    
    log_info "Deploying single service: $service"
    
    # Get service IP from manifest
    local service_ip
    if ! service_ip=$(get_service_ip "$service"); then
        log_error "Failed to get IP address for service $service"
        return 1
    fi
    
    # Deploy the service
    if ! deploy_service_via_ssh "$service" "$service_ip"; then
        log_error "Failed to deploy service $service"
        return 1
    fi
    
    log_success "Service $service deployment completed"
}

# Main deployment function
main() {
    log_info "Starting NixMox streamlined deployment orchestrator..."

    # Change to project root
    cd "$PROJECT_ROOT"

    # Check prerequisites
    check_prerequisites

    # Validate manifest
    validate_manifest

    # Check deployment mode
    if [[ -n "${TARGET_SERVICE:-}" ]]; then
        # Single service deployment
        log_info "Deploying single service: $TARGET_SERVICE"
        deploy_single_service "$TARGET_SERVICE"
    else
        # Full deployment (all steps)
        log_info "Deploying all phases (1-4)"
        log_info "Authentik mode: $AUTHENTIK_MODE"

        # Step 1: Terraform infrastructure
        deploy_terraform_infrastructure

        # Step 2: NixOS Core Services
        deploy_nixos_core_services

        # Step 3: Terraform Authentik Applications
        deploy_terraform_authentik

        # Step 4: Additional NixOS Services
        deploy_additional_nixos_services
    fi
    
    log_success "NixMox deployment completed successfully!"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    --dry-run          Show what would be deployed without actually deploying
    --service SERVICE   Deploy only the specified service
    --skip-terraform   Skip Terraform phases (infrastructure and Authentik)
    --skip-nixos       Skip NixOS deployment phases
    --authentik-mode MODE  Authentik deployment mode: "simple" (default) or "full"
    --secrets-file FILE Path to SOPS encrypted secrets file

Authentik Modes:
    simple              Deploy Authentik resources only (for updates/repeated deployments)
    full                Full deployment: deploy resources, update outpost tokens, re-deploy authentik

Examples:
    $0                           # Deploy all phases (1-4) with simple Authentik mode
    $0 --authentik-mode full    # Deploy all phases with full Authentik mode
    $0 --service vaultwarden    # Deploy only vaultwarden service
    $0 --dry-run                # Show deployment plan without executing
    $0 --skip-terraform         # Skip Terraform, only deploy NixOS services

Deployment Steps:
    1. Terraform infrastructure (Proxmox LXC containers from terraform/infrastructure/)
    2. NixOS Core Services (postgresql, dns, caddy, authentik)
    3. Terraform Authentik Applications (outposts, OIDC apps from terraform/authentik/)
    4. Additional NixOS services (vaultwarden, guacamole, etc.)

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
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-nixos)
            SKIP_NIXOS=true
            shift
            ;;
        --authentik-mode)
            AUTHENTIK_MODE="$2"
            if [[ "$AUTHENTIK_MODE" != "simple" && "$AUTHENTIK_MODE" != "full" ]]; then
                log_error "Invalid Authentik mode: $AUTHENTIK_MODE. Must be 'simple' or 'full'"
                exit 1
            fi
            shift 2
            ;;
        --secrets-file)
            SECRETS_FILE="$2"
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
