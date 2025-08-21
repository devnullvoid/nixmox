#!/usr/bin/env bash

set -euo pipefail

# NixMox Test Deployment Script
# This script builds NixOS configurations and prepares them for testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] CONTAINER_NAME

Build and prepare NixOS configurations for testing.

OPTIONS:
    -h, --help          Show this help message
    -o, --output DIR    Output directory for built systems (default: ./builds)
    -l, --list          List available containers
    -t, --test          Run basic configuration tests

CONTAINER_NAME:
    Name of the container to build (e.g., authentik, caddy, monitoring)

Available containers:
    - authentik
    - caddy
    - postgresql
    - nextcloud
    - media
    - monitoring
    - guacamole
    - vaultwarden
    - dns
    - mail

Examples:
    $0 authentik                    # Build authentik container
    $0 -o /tmp/builds caddy        # Build caddy container to /tmp/builds
    $0 -l                          # List available containers
    $0 -t authentik                # Test authentik configuration
EOF
}

# Default values
OUTPUT_DIR="./builds"
LIST_CONTAINERS=false
TEST_CONFIG=false
CONTAINER_NAME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -l|--list)
            LIST_CONTAINERS=true
            shift
            ;;
        -t|--test)
            TEST_CONFIG=true
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$CONTAINER_NAME" ]]; then
                CONTAINER_NAME="$1"
            else
                print_error "Multiple container names specified"
                exit 1
            fi
            shift
            ;;
    esac
done

# List available containers
if [[ "$LIST_CONTAINERS" == "true" ]]; then
    print_status "Available containers:"
    echo "  - authentik"
    echo "  - caddy"
    echo "  - postgresql"
    echo "  - nextcloud"
    echo "  - media"
    echo "  - monitoring"
    echo "  - guacamole"
    echo "  - vaultwarden"
    echo "  - dns"
    echo "  - mail"
    exit 0
fi

# Check if container name is provided
if [[ -z "$CONTAINER_NAME" ]]; then
    print_error "Container name is required"
    show_usage
    exit 1
fi

# Validate container name
VALID_CONTAINERS=("authentik" "caddy" "postgresql" "nextcloud" "media" "monitoring" "guacamole" "vaultwarden" "dns" "mail")
if [[ ! " ${VALID_CONTAINERS[@]} " =~ " ${CONTAINER_NAME} " ]]; then
    print_error "Invalid container name: $CONTAINER_NAME"
    print_status "Available containers: ${VALID_CONTAINERS[*]}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

print_status "Building NixOS configuration for $CONTAINER_NAME..."

# Build the NixOS configuration
if ! nix build ".#nixosConfigurations.$CONTAINER_NAME.config.system.build.toplevel" -o "$OUTPUT_DIR/$CONTAINER_NAME"; then
    print_error "Failed to build NixOS configuration for $CONTAINER_NAME"
    exit 1
fi

print_success "NixOS configuration built successfully"

# Test configuration if requested
if [[ "$TEST_CONFIG" == "true" ]]; then
    print_status "Testing configuration..."
    
    # Check if the main service is properly configured
    SERVICE_ENABLED=$(nix eval ".#nixosConfigurations.$CONTAINER_NAME.config.services.nixmox.$CONTAINER_NAME.enable" 2>/dev/null || echo "false")
    if [[ "$SERVICE_ENABLED" != "true" ]]; then
        print_warning "Main service not enabled - checking alternative configurations..."
        
        # For vaultwarden, check OCI configuration
        if [[ "$CONTAINER_NAME" == "vaultwarden" ]]; then
            OCI_ENABLED=$(nix eval ".#nixosConfigurations.$CONTAINER_NAME.config.services.nixmox.vaultwarden.oci.enable" --raw 2>/dev/null || echo "false")
            if [[ "$OCI_ENABLED" != "true" ]]; then
                print_error "Configuration test failed - Vaultwarden OCI service not properly configured"
                exit 1
            fi
        # For media, check if any media services are enabled
        elif [[ "$CONTAINER_NAME" == "media" ]]; then
            MEDIA_ENABLED=$(nix eval ".#nixosConfigurations.$CONTAINER_NAME.config.services.nixmox.media.enable" --raw 2>/dev/null || echo "false")
            if [[ "$MEDIA_ENABLED" != "true" ]]; then
                print_error "Configuration test failed - Media service not properly configured"
                exit 1
            fi
        else
            print_error "Configuration test failed - Main service not properly configured"
            exit 1
        fi
    fi
    
    # Check if the system has the expected packages
    PACKAGES=$(nix eval ".#nixosConfigurations.$CONTAINER_NAME.config.environment.systemPackages" --raw 2>/dev/null || echo "[]")
    if [[ "$PACKAGES" == "[]" ]]; then
        print_warning "Configuration test - no system packages found"
    fi
    
    print_success "Configuration test passed!"
fi

print_success "Build complete!"
print_status "Generated files:"
ls -la "$OUTPUT_DIR/$CONTAINER_NAME"

print_status "Next steps for testing:"
echo "  1. The built system is available at: $OUTPUT_DIR/$CONTAINER_NAME"
echo "  2. You can extract the system to test it:"
echo "     sudo tar -xf $OUTPUT_DIR/$CONTAINER_NAME/activate"
echo "  3. For LXC deployment, use the generate-lxc.sh script"
echo "  4. For SSH testing, the default credentials are:"
echo "     User: nixmox"
echo "     Password: nixmox"
echo "     (These should be changed after first login)" 