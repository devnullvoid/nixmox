#!/usr/bin/env bash

# Setup Authentik HTTP Basic authentication for *arr services
# This script creates the "Arr Users" group and configures proxy providers

set -euo pipefail

# Configuration
AUTHENTIK_URL="https://auth.nixmox.lan"

# Get Authentik token from SOPS secrets (same as Terraform)
if [ -f "secrets/default.yaml" ]; then
    AUTHENTIK_TOKEN=$(sops -d secrets/default.yaml | yq -r '.authentik_bootstrap_token')
    if [ "$AUTHENTIK_TOKEN" = "null" ] || [ -z "$AUTHENTIK_TOKEN" ]; then
        log_error "Failed to get authentik_bootstrap_token from secrets/default.yaml"
        exit 1
    fi
else
    log_error "secrets/default.yaml not found. Please run this script from the project root."
    exit 1
fi
GROUP_NAME="Arr Users"
USERNAME_ATTR="arr_user"
PASSWORD_ATTR="arr_password"
USERNAME_VALUE="admin"
PASSWORD_VALUE="admin123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to make API calls to Authentik
authentik_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    curl -s -k -X "$method" \
        -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$AUTHENTIK_URL/api/v3/$endpoint"
}

# Function to get existing group
get_group() {
    local group_name="$1"
    # URL encode the group name for the search parameter
    local encoded_name=$(printf '%s\n' "$group_name" | jq -sRr @uri)
    authentik_api "GET" "core/groups/?search=$encoded_name" "{}" | jq -r '.results[] | select(.name == "'"$group_name"'") | .pk // empty'
}

# Function to create group
create_group() {
    local group_name="$1"
    local username_attr="$2"
    local password_attr="$3"
    local username_value="$4"
    local password_value="$5"
    
    local data=$(cat <<EOF
{
    "name": "$group_name",
    "attributes": {
        "$username_attr": "$username_value",
        "$password_attr": "$password_value"
    }
}
EOF
)
    
    authentik_api "POST" "core/groups/" "$data"
}

# Function to get proxy providers
get_proxy_providers() {
    authentik_api "GET" "providers/proxy/" "{}" | jq -r '.results[] | select(.name | contains("media-")) | {pk: .pk, name: .name}'
}

# Function to update proxy provider for basic auth
update_proxy_provider() {
    local provider_pk="$1"
    local provider_name="$2"
    local username_attr="$3"
    local password_attr="$4"
    
    log_info "Updating proxy provider: $provider_name"
    
    local data=$(cat <<EOF
{
    "basic_auth_enabled": true,
    "basic_auth_user_attribute": "$username_attr",
    "basic_auth_password_attribute": "$password_attr"
}
EOF
)
    
    authentik_api "PATCH" "providers/proxy/$provider_pk/" "$data" > /dev/null
}

# Function to get users
get_users() {
    authentik_api "GET" "core/users/" "{}" | jq -r '.results[] | {pk: .pk, username: .username}'
}

# Function to add user to group
add_user_to_group() {
    local user_pk="$1"
    local group_pk="$2"
    
    local data=$(cat <<EOF
{
    "pk": $user_pk
}
EOF
)
    
    authentik_api "POST" "core/groups/$group_pk/users/" "$data" > /dev/null
}

# Main execution
main() {
    log_info "Setting up Authentik HTTP Basic authentication for *arr services"
    
    # Check if group already exists
    local existing_group_pk
    existing_group_pk=$(get_group "$GROUP_NAME")
    
    local group_pk
    if [ -n "$existing_group_pk" ]; then
        log_warn "Group '$GROUP_NAME' already exists (PK: $existing_group_pk)"
        group_pk="$existing_group_pk"
    else
        log_info "Creating group '$GROUP_NAME'"
        local group_response
        group_response=$(create_group "$GROUP_NAME" "$USERNAME_ATTR" "$PASSWORD_ATTR" "$USERNAME_VALUE" "$PASSWORD_VALUE")
        group_pk=$(echo "$group_response" | jq -r '.pk')
        log_info "Created group with PK: $group_pk"
    fi
    
    # Update proxy providers for *arr services
    log_info "Updating proxy providers for basic authentication"
    local providers
    providers=$(get_proxy_providers)
    
    echo "$providers" | jq -c '.' | while read -r provider; do
        local provider_pk
        local provider_name
        provider_pk=$(echo "$provider" | jq -r '.pk')
        provider_name=$(echo "$provider" | jq -r '.name')
        
        # Skip transmission
        if [[ "$provider_name" == *"transmission"* ]]; then
            log_info "Skipping transmission provider (doesn't need basic auth)"
            continue
        fi
        
        update_proxy_provider "$provider_pk" "$provider_name" "$USERNAME_ATTR" "$PASSWORD_ATTR"
    done
    
    # Add users to group (optional - you can specify which users to add)
    log_info "Available users:"
    get_users | jq -r '.username' | while read -r username; do
        echo "  - $username"
    done
    
    log_info "To add users to the '$GROUP_NAME' group, run:"
    log_info "  ./scripts/authentik/add-user-to-group.sh <username> '$GROUP_NAME'"
    
    log_info "Setup complete! *arr services should now use HTTP Basic authentication."
    log_info "Credentials: username='$USERNAME_VALUE', password='$PASSWORD_VALUE'"
}

# Run main function
main "$@"

