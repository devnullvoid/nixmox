#!/usr/bin/env bash

set -euo pipefail

# NixMox LXC Image Generator
# This script generates Proxmox LXC images from NixOS configurations

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

Generate Proxmox LXC images from NixOS configurations.

OPTIONS:
    -h, --help          Show this help message
    -o, --output DIR    Output directory for generated images (default: ./images)
    -f, --format FORMAT Image format (default: proxmox-lxc)
    -l, --list          List available containers

CONTAINER_NAME:
    Name of the container to build (e.g., authentik, caddy, monitoring)

Available containers:
    - authentik
    - caddy
    - monitoring
    - mail (planned)
    - media (planned)
    - nextcloud (planned)
    - vaultwarden (planned)
    - dns (planned)

Examples:
    $0 authentik                    # Build authentik container
    $0 -o /tmp/images caddy        # Build caddy container to /tmp/images
    $0 -l                          # List available containers
EOF
}

# Default values
OUTPUT_DIR="./images"
FORMAT="proxmox-lxc"
LIST_CONTAINERS=false
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
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -l|--list)
            LIST_CONTAINERS=true
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
    echo "  - monitoring"
    echo "  - mail (planned)"
    echo "  - media (planned)"
    echo "  - nextcloud (planned)"
    echo "  - vaultwarden (planned)"
    echo "  - dns (planned)"
    exit 0
fi

# Check if container name is provided
if [[ -z "$CONTAINER_NAME" ]]; then
    print_error "Container name is required"
    show_usage
    exit 1
fi

# Validate container name
VALID_CONTAINERS=("authentik" "caddy" "monitoring")
if [[ ! " ${VALID_CONTAINERS[@]} " =~ " ${CONTAINER_NAME} " ]]; then
    print_error "Invalid container name: $CONTAINER_NAME"
    print_status "Available containers: ${VALID_CONTAINERS[*]}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

print_status "Building NixOS configuration for $CONTAINER_NAME..."

# Build the NixOS configuration
if ! nix build ".#nixosConfigurations.$CONTAINER_NAME.config.system.build.toplevel" --no-link; then
    print_error "Failed to build NixOS configuration for $CONTAINER_NAME"
    exit 1
fi

print_success "NixOS configuration built successfully"

print_status "Generating $FORMAT image..."

# Generate the LXC image
cd "$PROJECT_ROOT"
if ! nix develop --command nixos-generators -f "$FORMAT" -c ".#nixosConfigurations.$CONTAINER_NAME" -o "$OUTPUT_DIR"; then
    print_error "Failed to generate $FORMAT image for $CONTAINER_NAME"
    exit 1
fi

print_success "Generated $FORMAT image for $CONTAINER_NAME in $OUTPUT_DIR"

# Show the generated files
print_status "Generated files:"
ls -la "$OUTPUT_DIR"/*"$CONTAINER_NAME"* 2>/dev/null || print_warning "No files found matching pattern"

print_success "LXC image generation complete!"
print_status "Next steps:"
echo "  1. Upload the generated image to your Proxmox host"
echo "  2. Create a new LXC container using the uploaded image"
echo "  3. Configure the container with appropriate resources"
echo "  4. Start the container and test SSH connectivity"
echo ""
echo "SSH connection details:"
echo "  Host: <container-ip>"
echo "  Port: 22"
echo "  User: nixmox"
echo "  Password: nixmox (temporary, change after first login)" 