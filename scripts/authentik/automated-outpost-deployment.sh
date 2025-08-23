#!/usr/bin/env bash

# Automated Authentik Outpost Deployment Pipeline
# This script handles the complete process from Terraform outpost creation
# to token retrieval, secrets update, and redeployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/authentik"
SECRETS_FILE="$PROJECT_ROOT/secrets/default.yaml"
SECRETS_DECRYPTED="$PROJECT_ROOT/secrets/default.decrypted.yaml"
AUTHENTIK_HOST="https://auth.nixmox.lan"
AUTHENTIK_CONTAINER="authentik"
AUTHENTIK_IP="192.168.99.12"

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

# Check if required tools are available
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
    
    # Decrypt secrets temporarily to get bootstrap token
    local temp_decrypted
    temp_decrypted=$(mktemp)
    sops -d "$SECRETS_FILE" > "$temp_decrypted" 2>/dev/null || {
        log_error "Failed to decrypt secrets file"
        rm -f "$temp_decrypted"
        exit 1
    }
    
    local bootstrap_token
    bootstrap_token=$(grep "AUTHENTIK_BOOTSTRAP_TOKEN=" "$temp_decrypted" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    
    rm -f "$temp_decrypted"
    
    if [[ -z "$bootstrap_token" ]]; then
        log_error "Could not extract bootstrap token from secrets"
        exit 1
    fi
    
    log_success "Bootstrap token extracted successfully"
    echo "$bootstrap_token"
}

# Deploy Terraform configuration for a specific outpost type
deploy_terraform_outpost() {
    local outpost_type="$1"
    local terraform_dir="$TERRAFORM_DIR/$outpost_type"
    
    if [[ ! -d "$terraform_dir" ]]; then
        log_error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    log_info "Deploying $outpost_type outpost with Terraform..."
    
    cd "$terraform_dir"
    
    # Initialize Terraform if needed
    if [[ ! -d ".terraform" ]]; then
        log_info "Initializing Terraform..."
        terraform init
    fi
    
    # Plan and apply
    log_info "Planning Terraform changes..."
    terraform plan -out=tfplan
    
    log_info "Applying Terraform configuration..."
    terraform apply tfplan
    
    # Get the outpost ID from output
    local outpost_id
    outpost_id=$(terraform output -raw outpost_id)
    
    log_success "$outpost_type outpost deployed with ID: $outpost_id"
    
    # Return to project root
    cd "$PROJECT_ROOT"
    
    echo "$outpost_id"
}

# Wait for outpost to be ready and get its token
wait_for_outpost_and_get_token() {
    local outpost_id="$1"
    local bootstrap_token="$2"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for outpost $outpost_id to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: Checking outpost status..."
        
        # Check if outpost is accessible via API
        local response
        response=$(curl -k -s -w "%{http_code}" \
            "$AUTHENTIK_HOST/api/v3/core/outposts/?search=$outpost_id" \
            -H "Authorization: Bearer $bootstrap_token" \
            -o /tmp/outpost_response.json)
        
        if [[ "$response" == "200" ]]; then
            # Check if outpost is in the response
            if jq -e ".results[] | select(.pk == \"$outpost_id\")" /tmp/outpost_response.json >/dev/null 2>&1; then
                log_success "Outpost $outpost_id is ready"
                break
            fi
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Outpost $outpost_id did not become ready after $max_attempts attempts"
            rm -f /tmp/outpost_response.json
            return 1
        fi
        
        log_info "Outpost not ready yet, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    rm -f /tmp/outpost_response.json
    
    # Now get the token
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

# Update secrets file with new outpost tokens
update_secrets_with_tokens() {
    local ldap_token="$1"
    local radius_token="$2"
    
    log_info "Updating secrets file with new outpost tokens..."
    
    # Decrypt secrets file
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
    
    # Create backup of encrypted file
    local backup_file="$SECRETS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SECRETS_FILE" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # Re-encrypt the updated file
    log_info "Re-encrypting secrets file..."
    cp "$SECRETS_DECRYPTED" "$SECRETS_FILE"
    sops -e --in-place "$SECRETS_FILE"
    
    log_success "Secrets file updated and re-encrypted successfully"
}

# Deploy updated configuration to Authentik container
redeploy_authentik() {
    log_info "Redeploying Authentik with updated configuration..."
    
    if [[ ! -f "$PROJECT_ROOT/scripts/deploy-nixos.sh" ]]; then
        log_error "Deploy script not found: $PROJECT_ROOT/scripts/deploy-nixos.sh"
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

# Verify outpost services are running
verify_outpost_services() {
    local max_attempts=20
    local attempt=1
    
    log_info "Verifying outpost services are running..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: Checking service status..."
        
        # Check service status via SSH
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
    
    # Show final service status
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
    
    # Deploy LDAP outpost
    log_info "=== Deploying LDAP Outpost ==="
    local ldap_outpost_id
    ldap_outpost_id=$(deploy_terraform_outpost "ldap")
    
    # Deploy Radius outpost
    log_info "=== Deploying Radius Outpost ==="
    local radius_outpost_id
    radius_outpost_id=$(deploy_terraform_outpost "radius")
    
    # Wait for outposts to be ready and get tokens
    log_info "=== Waiting for Outposts and Retrieving Tokens ==="
    local ldap_token
    ldap_token=$(wait_for_outpost_and_get_token "$ldap_outpost_id" "$bootstrap_token")
    
    local radius_token
    radius_token=$(wait_for_outpost_and_get_token "$radius_outpost_id" "$bootstrap_token")
    
    # Update secrets file
    log_info "=== Updating Secrets File ==="
    update_secrets_with_tokens "$ldap_token" "$radius_token"
    
    # Redeploy Authentik
    log_info "=== Redeploying Authentik ==="
    redeploy_authentik
    
    # Verify services
    log_info "=== Verifying Outpost Services ==="
    verify_outpost_services
    
    log_success "=== Automated outpost deployment completed successfully! ==="
    log_info "LDAP Outpost ID: $ldap_outpost_id"
    log_info "Radius Outpost ID: $radius_outpost_id"
    log_info "Both outposts are now running with updated tokens"
}

# Run main function
main "$@"
