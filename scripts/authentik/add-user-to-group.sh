#!/usr/bin/env bash

# Add a user to an Authentik group
# Usage: ./add-user-to-group.sh <username> <group_name>

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

# Function to get user by username
get_user() {
    local username="$1"
    # URL encode the username for the search parameter
    local encoded_name=$(printf '%s\n' "$username" | jq -sRr @uri)
    authentik_api "GET" "core/users/?search=$encoded_name" "{}" | jq -r '.results[] | select(.username == "'"$username"'") | .pk // empty'
}

# Function to get group by name
get_group() {
    local group_name="$1"
    # URL encode the group name for the search parameter
    local encoded_name=$(printf '%s\n' "$group_name" | jq -sRr @uri)
    authentik_api "GET" "core/groups/?search=$encoded_name" "{}" | jq -r '.results[] | select(.name == "'"$group_name"'") | .pk // empty'
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
    
    authentik_api "POST" "core/groups/$group_pk/users/" "$data"
}

# Main execution
main() {
    if [ $# -ne 2 ]; then
        log_error "Usage: $0 <username> <group_name>"
        exit 1
    fi
    
    local username="$1"
    local group_name="$2"
    
    log_info "Adding user '$username' to group '$group_name'"
    
    # Get user PK
    local user_pk
    user_pk=$(get_user "$username")
    if [ -z "$user_pk" ]; then
        log_error "User '$username' not found"
        exit 1
    fi
    log_info "Found user '$username' (PK: $user_pk)"
    
    # Get group PK
    local group_pk
    group_pk=$(get_group "$group_name")
    if [ -z "$group_pk" ]; then
        log_error "Group '$group_name' not found"
        exit 1
    fi
    log_info "Found group '$group_name' (PK: $group_pk)"
    
    # Add user to group
    log_info "Adding user to group..."
    add_user_to_group "$user_pk" "$group_pk"
    
    log_info "Successfully added user '$username' to group '$group_name'"
}

# Run main function
main "$@"

