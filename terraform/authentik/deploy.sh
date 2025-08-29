#!/bin/bash

# Deploy Authentik Resources Only
# This manages only Authentik resources, never touches LXC containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SECRETS_FILE:-../../secrets/default.yaml}"

echo "🚀 Deploying Authentik Resources..."
echo "📁 Directory: $SCRIPT_DIR"
echo "🔐 Secrets file: $SECRETS_FILE"
echo

# Validate that secrets file exists if specified
if [ "$SECRETS_FILE" != "" ] && [ ! -f "$SECRETS_FILE" ]; then
    echo "❌ Secrets file not found: $SECRETS_FILE"
    exit 1
fi

# Change to the authentik directory
cd "$SCRIPT_DIR"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "📦 Initializing Terraform..."
    terraform init
fi

# Plan the authentik deployment
echo "📋 Planning Authentik resources deployment..."
terraform plan \
    -var="secrets_file=$SECRETS_FILE" \
    -out=authentik-plan.tfplan

echo
echo "✅ Authentik resources plan created: authentik-plan.tfplan"
echo
echo "💡 To apply the changes, run:"
echo "   cd terraform/authentik && terraform apply authentik-plan.tfplan"
echo
echo "📊 This will deploy ALL Authentik resources from the manifest"
