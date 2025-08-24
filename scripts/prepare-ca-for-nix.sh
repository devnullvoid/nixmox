#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration
CA_DIR="certs"
NIX_CA_DIR="nixos/ca"
CA_NAME="nixmox-internal-ca"

# Check if we're in the right directory
if [[ ! -f "flake.nix" ]]; then
    log_error "This script must be run from the nixmox project root directory"
    exit 1
fi

# Check if CA certificates exist
if [[ ! -f "$CA_DIR/$CA_NAME.crt" ]] || [[ ! -f "$CA_DIR/$CA_NAME.key" ]]; then
    log_error "CA certificates not found. Run ./scripts/generate-ca.sh first."
    exit 1
fi

# Create Nix-accessible CA directory
log_info "Creating Nix-accessible CA directory..."
mkdir -p "$NIX_CA_DIR"

# Copy CA certificates
log_info "Copying CA certificates to Nix-accessible location..."
cp "$CA_DIR/$CA_NAME.crt" "$NIX_CA_DIR/"
cp "$CA_DIR/$CA_NAME.key" "$NIX_CA_DIR/"

# Set proper permissions
chmod 644 "$NIX_CA_DIR/$CA_NAME.crt"
chmod 600 "$NIX_CA_DIR/$CA_NAME.key"

log_success "CA certificates prepared for Nix deployment!"
log_info "Certificates are now available at:"
log_info "  - $NIX_CA_DIR/$CA_NAME.crt"
log_info "  - $NIX_CA_DIR/$CA_NAME.key"
log_info ""
log_info "You can now deploy Caddy with:"
log_info "  ./scripts/deploy-nixos.sh caddy"
