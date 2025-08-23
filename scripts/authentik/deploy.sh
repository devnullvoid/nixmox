#!/usr/bin/env bash

# Quick Authentik Outpost Deployment Wrapper
# Simple script to run the full automated deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Starting Authentik Outpost Deployment..."
echo "This will:"
echo "  1. Deploy LDAP and Radius outposts via Terraform"
echo "  2. Wait for outposts to be ready"
echo "  3. Retrieve fresh outpost tokens"
echo "  4. Update the secrets file"
echo "  5. Redeploy Authentik with new configuration"
echo "  6. Verify all services are running"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "Starting deployment in 3 seconds..."
sleep 3

# Run the main deployment script
"$SCRIPT_DIR/deploy-outposts.sh" "$@"
