#!/usr/bin/env bash

# Script to get the embedded outpost ID from Authentik
# This can be used to dynamically discover the embedded outpost ID

set -euo pipefail

# Get bootstrap token from SOPS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_TOKEN=$(sops -d "$SCRIPT_DIR/../secrets/default.yaml" | grep authentik_bootstrap_token | cut -d' ' -f2)

# Extract Authentik configuration from manifest
AUTHENTIK_CONFIG=$(nix eval --json --file "$SCRIPT_DIR/../nixos/service-manifest.nix" 'core_services.authentik' 2>/dev/null || echo "{}")
AUTHENTIK_IP=$(echo "$AUTHENTIK_CONFIG" | jq -r '.ip // "192.168.99.12"')
AUTHENTIK_DOMAIN=$(echo "$AUTHENTIK_CONFIG" | jq -r '.interface.proxy.domain // "auth.nixmox.lan"')

# Build API endpoints from manifest data
ENDPOINTS=(
  "https://$AUTHENTIK_DOMAIN/api/v3/outposts/instances/"
  "http://$AUTHENTIK_IP:9000/api/v3/outposts/instances/"
)

# Debug output (to stderr so it doesn't interfere with JSON output)
echo "Using Authentik IP: $AUTHENTIK_IP, Domain: $AUTHENTIK_DOMAIN" >&2

# Try different API endpoints
for endpoint in "${ENDPOINTS[@]}"; do
    # Query Authentik API for outposts
    RESPONSE=$(curl -s -H "Authorization: Bearer $BOOTSTRAP_TOKEN" "$endpoint" 2>/dev/null || echo "")
    
    # Check if we got JSON response
    if echo "$RESPONSE" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        # Extract embedded outpost ID
        OUTPOST_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for outpost in data['results']:
        if outpost['name'] == 'authentik Embedded Outpost' and outpost['type'] == 'proxy':
            print(outpost['pk'])
            break
except:
    pass
")
        
        if [ -n "$OUTPOST_ID" ]; then
            echo "{\"id\": \"$OUTPOST_ID\"}"
            exit 0
        fi
    fi
done

# Fallback to known ID if API fails
echo "{\"id\": \"28c9a870-5d34-468e-9fb2-63cfdc21c997\"}"
