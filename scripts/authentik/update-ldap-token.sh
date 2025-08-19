#!/usr/bin/env bash

# Simple wrapper to update LDAP outpost token using Terraform output
# This script updates the encrypted secrets file using sops
# Usage: ./update-ldap-token.sh [authentik-admin-token]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="$SCRIPT_DIR/update-outpost-tokens-simple.sh"

# Get the LDAP outpost ID from Terraform output
cd /home/jon/Dev/github/nixmox/terraform/authentik/ldap

if ! LDAP_OUTPOST_ID=$(terraform output -raw ldap_outpost_id 2>/dev/null); then
    echo "Error: Failed to get LDAP outpost ID from Terraform output"
    echo "Make sure you're in the LDAP terraform directory and have run 'terraform apply'"
    exit 1
fi

echo "LDAP Outpost ID: $LDAP_OUTPOST_ID"

# Get admin token from command line or prompt
if [[ $# -eq 1 ]]; then
    AUTHENTIK_ADMIN_TOKEN="$1"
else
    echo -n "Enter Authentik admin token: "
    read -s AUTHENTIK_ADMIN_TOKEN
    echo
fi

if [[ -z "$AUTHENTIK_ADMIN_TOKEN" ]]; then
    echo "Error: Admin token is required"
    exit 1
fi

# Export variables and run the update script
export AUTHENTIK_ADMIN_TOKEN="$AUTHENTIK_ADMIN_TOKEN"
export LDAP_OUTPOST_ID="$LDAP_OUTPOST_ID"

echo "Updating LDAP outpost token in encrypted secrets file..."
"$UPDATE_SCRIPT" -t "$AUTHENTIK_ADMIN_TOKEN" -l "$LDAP_OUTPOST_ID"
