#!/bin/bash

# Generate NixOS network configuration from Terraform outputs
# This script ensures Terraform is the single source of truth for network configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/phases"
OUTPUT_FILE="$PROJECT_ROOT/nixos/network-config.nix"

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

# Check if we're in the right directory
if [[ ! -f "$TERRAFORM_DIR/main.tf" ]]; then
    log_error "Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

# Change to Terraform directory
cd "$TERRAFORM_DIR"

# Check if Terraform is initialized
if [[ ! -d ".terraform" ]]; then
    log_error "Terraform not initialized. Run 'terraform init' first."
    exit 1
fi

# Get Terraform outputs
log_info "Getting Terraform outputs..."
if ! terraform output -json > /tmp/terraform_outputs.json 2>/dev/null; then
    log_error "Failed to get Terraform outputs. Make sure Terraform state is available."
    exit 1
fi

# Generate NixOS network configuration
log_info "Generating NixOS network configuration..."
cd "$PROJECT_ROOT"

if ! nix eval -f scripts/generate-network-config.nix --arg terraformOutputs "$(cat /tmp/terraform_outputs.json)" > "$OUTPUT_FILE.tmp" 2>/dev/null; then
    log_error "Failed to generate NixOS network configuration"
    exit 1
fi

# Format the output nicely
nix fmt "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE" 2>/dev/null || cp "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.tmp"

log_info "Network configuration generated: $OUTPUT_FILE"

# Show summary of what was generated
log_info "Generated configuration includes:"
echo "  - Network infrastructure (DNS server, gateway, CIDR)"
echo "  - Container network configurations"
echo "  - DNS records for Unbound"
echo "  - Host mappings for /etc/hosts"

# Clean up temporary files
rm -f /tmp/terraform_outputs.json

log_info "Done! You can now import this configuration in your NixOS modules."
