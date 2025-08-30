#!/usr/bin/env bash

# Authentik Outpost Deployment Script
# Automated pipeline for deploying outposts, retrieving tokens, and updating secrets

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/outpost-config.yaml"

# Import configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Load configuration using yq (fallback to grep if not available)
load_config() {
    local key="$1"
    local default="$2"
    
    if command -v yq >/dev/null 2>&1; then
        yq -r "$key" "$CONFIG_FILE" 2>/dev/null || echo "$default"
    else
        # Fallback to grep-based parsing
        case "$key" in
            ".authentik.host")
                grep -A 5 "authentik:" "$CONFIG_FILE" | grep "host:" | cut -d':' -f2 | tr -d ' "'
                ;;
            ".authentik.container")
                grep -A 5 "authentik:" "$CONFIG_FILE" | grep "container:" | cut -d':' -f2 | tr -d ' "'
                ;;
            ".authentik.ip")
                grep -A 5 "authentik:" "$CONFIG_FILE" | grep "ip:" | cut -d':' -f2 | tr -d ' "'
                ;;
            ".authentik.bootstrap_token_env")
                grep -A 5 "authentik:" "$CONFIG_FILE" | grep "bootstrap_token_env:" | cut -d':' -f2 | tr -d ' "'
                ;;
            ".terraform.base_dir")
                grep -A 5 "terraform:" "$CONFIG_FILE" | grep "base_dir:" | cut -d':' -f2 | tr -d ' "'
                ;;
            ".secrets.encrypted_file")
                grep -A 5 "secrets:" "$CONFIG_FILE" | grep "encrypted_file:" | cut -d':' -f2 | tr -d ' "'
                ;;
            ".secrets.decrypted_file")
                grep -A 5 "secrets:" "$CONFIG_FILE" | grep "decrypted_file:" | cut -d':' -f2 | tr -d ' "'
                ;;
            ".deployment.max_wait_attempts")
                grep -A 5 "deployment:" "$CONFIG_FILE" | grep "max_wait_attempts:" | cut -d':' -f2 | tr -d ' "'
                ;;
            *)
                echo "$default"
                ;;
        esac
    fi
}

# Configuration variables
AUTHENTIK_HOST=$(load_config ".authentik.host" "https://auth.nixmox.lan")
AUTHENTIK_CONTAINER=$(load_config ".authentik.container" "authentik")
AUTHENTIK_IP=$(load_config ".authentik.ip" "192.168.99.12")
BOOTSTRAP_TOKEN_ENV=$(load_config ".authentik.bootstrap_token_env" "AUTHENTIK_BOOTSTRAP_TOKEN")
TERRAFORM_BASE_DIR="$PROJECT_ROOT/$(load_config ".terraform.base_dir" "terraform/authentik")"
SECRETS_FILE="$PROJECT_ROOT/$(load_config ".secrets.encrypted_file" "secrets/default.yaml")"
SECRETS_DECRYPTED="$PROJECT_ROOT/$(load_config ".secrets.decrypted_file" "secrets/default.decrypted.yaml")"
MAX_WAIT_ATTEMPTS=$(load_config ".deployment.max_wait_attempts" "30")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check requirements
check_requirements() {
    log_info "Checking requirements..."
    local missing_tools=()
    
    for tool in terraform sops ssh scp jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log_success "All required tools are available"
}

# Get bootstrap token from secrets
get_bootstrap_token() {
    log_info "Extracting bootstrap token from secrets..."
    
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "Secrets file not found: $SECRETS_FILE"
        exit 1
    fi
    
    local temp_decrypted
    temp_decrypted=$(mktemp)
    sops -d "$SECRETS_FILE" > "$temp_decrypted" 2>/dev/null || {
        log_error "Failed to decrypt secrets file"
        rm -f "$temp_decrypted"
        exit 1
    }
    
    local bootstrap_token
    bootstrap_token=$(grep "$BOOTSTRAP_TOKEN_ENV=" "$temp_decrypted" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    
    rm -f "$temp_decrypted"
    
    if [[ -z "$bootstrap_token" ]]; then
        log_error "Could not extract bootstrap token from secrets"
        exit 1
    fi
    
    log_success "Bootstrap token extracted successfully"
    echo "$bootstrap_token"
}

# Deploy single outpost with Terraform
deploy_outpost() {
    local outpost_type="$1"
    local terraform_dir="$TERRAFORM_BASE_DIR/$outpost_type"
    
    if [[ ! -d "$terraform_dir" ]]; then
        log_error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    log_info "Deploying $outpost_type outpost..."
    
    cd "$terraform_dir"
    
    # Initialize if needed
    if [[ ! -d ".terraform" ]]; then
        log_info "Initializing Terraform..."
        terraform init
    fi
    
    # Plan and apply
    log_info "Planning Terraform changes..."
    terraform plan -out=tfplan
    
    log_info "Applying Terraform configuration..."
    terraform apply tfplan
    
    # Get outpost ID
    local outpost_id
    outpost_id=$(terraform output -raw outpost_id)
    
    log_success "$outpost_type outpost deployed with ID: $outpost_id"
    
    cd "$PROJECT_ROOT"
    echo "$outpost_id"
}

# Wait for outpost to be ready
wait_for_outpost() {
    local outpost_id="$1"
    local bootstrap_token="$2"
    local attempt=1
    
    log_info "Waiting for outpost $outpost_id to be ready..."
    
    while [[ $attempt -le $MAX_WAIT_ATTEMPTS ]]; do
        log_info "Attempt $attempt/$MAX_WAIT_ATTEMPTS: Checking outpost status..."
        
        local response
        response=$(curl -k -s -w "%{http_code}" \
            "$AUTHENTIK_HOST/api/v3/core/outposts/?search=$outpost_id" \
            -H "Authorization: Bearer $bootstrap_token" \
            -o /tmp/outpost_response.json)
        
        if [[ "$response" == "200" ]]; then
            if jq -e ".results[] | select(.pk == \"$outpost_id\")" /tmp/outpost_response.json >/dev/null 2>&1; then
                log_success "Outpost $outpost_id is ready"
                rm -f /tmp/outpost_response.json
                return 0
            fi
        fi
        
        if [[ $attempt -eq $MAX_WAIT_ATTEMPTS ]]; then
            log_error "Outpost $outpost_id did not become ready after $MAX_WAIT_ATTEMPTS attempts"
            rm -f /tmp/outpost_response.json
            return 1
        fi
        
        log_info "Outpost not ready yet, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
}

# Get outpost token
get_outpost_token() {
    local outpost_id="$1"
    local bootstrap_token="$2"
    
    log_info "Retrieving token for outpost $outpost_id..."
    
    local token_response
    token_response=$(curl -k -s \
        "$AUTHENTIK_HOST/api/v3/core/tokens/ak-outpost-$outpost_id-api/view_key/" \
        -H "Authorization: Bearer $bootstrap_token")
    
    local token
    token=$(echo "$token_response" | jq -r '.key')
    
    if [[ "$token" == "null" ]] || [[ -z "$token" ]]; then
        log_error "Failed to retrieve token for outpost $outpost_id"
        return 1
    fi
    
    log_success "Token retrieved for outpost $outpost_id"
    echo "$token"
}

# Update secrets with new tokens
update_secrets() {
    local ldap_token="$1"
    local radius_token="$2"
    
    log_info "Updating secrets file with new outpost tokens..."
    
    # Create decrypted file if needed
    if [[ ! -f "$SECRETS_DECRYPTED" ]]; then
        log_info "Creating decrypted secrets file..."
        sops -d "$SECRETS_FILE" > "$SECRETS_DECRYPTED"
    fi
    
    # Update LDAP token
    log_info "Updating LDAP outpost token..."
    sed -i "s/AUTHENTIK_TOKEN=.*/AUTHENTIK_TOKEN=$ldap_token/" "$SECRETS_DECRYPTED"
    
    # Update Radius token
    log_info "Updating Radius outpost token..."
    sed -i "s/AUTHENTIK_TOKEN=.*/AUTHENTIK_TOKEN=$radius_token/" "$SECRETS_DECRYPTED"
    
    # Create backup
    local backup_file="$SECRETS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SECRETS_FILE" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # Re-encrypt
    log_info "Re-encrypting secrets file..."
    cp "$SECRETS_DECRYPTED" "$SECRETS_FILE"
    sops -e --in-place "$SECRETS_FILE"
    
    log_success "Secrets file updated and re-encrypted successfully"
}

# Redeploy Authentik
redeploy_authentik() {
    log_info "Redeploying Authentik with updated configuration..."
    
    if [[ ! -f "$PROJECT_ROOT/scripts/deploy-nixos.sh" ]]; then
        log_error "Deploy script not found"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
    
    if ./scripts/deploy-nixos.sh "$AUTHENTIK_CONTAINER"; then
        log_success "Authentik redeployed successfully"
    else
        log_error "Failed to redeploy Authentik"
        return 1
    fi
}

# Verify outpost services
verify_services() {
    local max_attempts=12
    local attempt=1
    
    log_info "Verifying outpost services are running..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: Checking service status..."
        
        local status_output
        status_output=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$AUTHENTIK_IP" \
            "systemctl is-active authentik-ldap.service authentik-radius.service" 2>/dev/null || true)
        
        if echo "$status_output" | grep -q "active" && echo "$status_output" | wc -l -eq 2; then
            log_success "Both outpost services are running"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Outpost services did not start properly after $max_attempts attempts"
            return 1
        fi
        
        log_info "Services not ready yet, waiting 15 seconds..."
        sleep 15
        ((attempt++))
    done
    
    # Show final status
    log_info "Final service status:"
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$AUTHENTIK_IP" \
        "systemctl status authentik-ldap.service authentik-radius.service --no-pager -l" | tail -20
}

# Main deployment function
main() {
    log_info "Starting automated Authentik outpost deployment pipeline..."
    
    # Check requirements
    check_requirements
    
    # Get bootstrap token
    local bootstrap_token
    bootstrap_token=$(get_bootstrap_token)
    
    # Deploy outposts
    log_info "=== Deploying Outposts ==="
    local ldap_outpost_id
    ldap_outpost_id=$(deploy_outpost "ldap")
    
    local radius_outpost_id
    radius_outpost_id=$(deploy_outpost "radius")
    
    # Wait for outposts and get tokens
    log_info "=== Waiting for Outposts and Retrieving Tokens ==="
    
    wait_for_outpost "$ldap_outpost_id" "$bootstrap_token"
    local ldap_token
    ldap_token=$(get_outpost_token "$ldap_outpost_id" "$bootstrap_token")
    
    wait_for_outpost "$radius_outpost_id" "$bootstrap_token"
    local radius_token
    radius_token=$(get_outpost_token "$radius_outpost_id" "$bootstrap_token")
    
    # Update secrets
    log_info "=== Updating Secrets File ==="
    update_secrets "$ldap_token" "$radius_token"
    
    # Redeploy Authentik
    log_info "=== Redeploying Authentik ==="
    redeploy_authentik
    
    # Verify services
    log_info "=== Verifying Outpost Services ==="
    verify_services
    
    log_success "=== Automated outpost deployment completed successfully! ==="
    log_info "LDAP Outpost ID: $ldap_outpost_id"
    log_info "Radius Outpost ID: $radius_outpost_id"
    log_info "Both outposts are now running with updated tokens"
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -c, --config   Use custom config file (default: outpost-config.yaml)"
    echo "  -v, --verbose  Enable verbose logging"
    echo ""
    echo "This script automates the complete Authentik outpost deployment process:"
    echo "1. Deploy outposts using Terraform"
    echo "2. Wait for outposts to be ready"
    echo "3. Retrieve outpost tokens"
    echo "4. Update secrets file"
    echo "5. Redeploy Authentik"
    echo "6. Verify services are running"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
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
