#!/usr/bin/env bash

# Script to retrieve Vaultwarden OIDC credentials from Authentik

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AUTHENTIK_URL="http://authentik.nixmox.lan:9000"
AUTHENTIK_TOKEN="28d9edfd2f6bfcab0c5305e30fb4ac4a4f10dc417843359f1dae1515ab12b03e"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_info "Retrieving Vaultwarden OIDC credentials from Authentik..."

# Get the OAuth2 provider details
PROVIDER_RESPONSE=$(curl -s -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
    "$AUTHENTIK_URL/api/v3/providers/oauth2/?name=Vaultwarden%20OIDC")

# Extract the provider ID and client credentials
PROVIDER_ID=$(echo "$PROVIDER_RESPONSE" | jq -r '.results[0].pk')
CLIENT_ID=$(echo "$PROVIDER_RESPONSE" | jq -r '.results[0].client_id')
CLIENT_SECRET=$(echo "$PROVIDER_RESPONSE" | jq -r '.results[0].client_secret')

if [[ "$PROVIDER_ID" == "null" ]] || [[ -z "$PROVIDER_ID" ]]; then
    echo "❌ Failed to retrieve provider information"
    exit 1
fi

log_success "Vaultwarden OIDC Provider ID: $PROVIDER_ID"
log_success "Client ID: $CLIENT_ID"
log_success "Client Secret: $CLIENT_SECRET"

echo
echo "🔑 Vaultwarden OIDC Configuration:"
echo "=================================="
echo "Provider ID: $PROVIDER_ID"
echo "Client ID: $CLIENT_ID"
echo "Client Secret: $CLIENT_SECRET"
echo "Redirect URI: https://vault.nixmox.lan/oidc/callback"
echo "Issuer URL: $AUTHENTIK_URL/application/o/vaultwarden/"
echo
echo "📝 Add these to your Vaultwarden configuration:"
echo "================================================"
echo "OIDC_ISSUER_PATH=/application/o/vaultwarden/"
echo "OIDC_CLIENT_ID=$CLIENT_ID"
echo "OIDC_CLIENT_SECRET=$CLIENT_SECRET"
echo "OIDC_REDIRECT_URI=https://vault.nixmox.lan/oidc/callback"
