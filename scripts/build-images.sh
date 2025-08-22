#!/usr/bin/env bash
set -euo pipefail

# NixMox LXC Image Builder
# This script builds Proxmox LXC images from NixOS configurations

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
Usage: $0 [OPTIONS] [HOSTS...]

Build Proxmox LXC images from NixOS configurations.

OPTIONS:
    -h, --help          Show this help message
    -o, --output DIR    Output directory for generated images (default: ./images)
    -f, --format FORMAT Image format (default: proxmox-lxc)
    -l, --list          List available hosts
    -a, --all           Build all hosts
    -c, --clean         Clean output directory before building

HOSTS:
    Space-separated list of hosts to build. If none specified, builds all.

Available hosts:
    - caddy
    - postgresql
    - authentik
    - nextcloud
    - media
    - monitoring
    - guacamole
    - vaultwarden
    - dns
    - mail

Examples:
    $0 authentik                    # Build authentik host
    $0 -o /tmp/images caddy        # Build caddy host to /tmp/images
    $0 -l                          # List available hosts
    $0 -a                          # Build all hosts
    $0 -c -a                       # Clean and build all hosts
EOF
}

# Default values
OUTPUT_DIR="./images"
FORMAT="proxmox-lxc"
LIST_HOSTS=false
BUILD_ALL=false
CLEAN_OUTPUT=false
HOSTS=()

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
            LIST_HOSTS=true
            shift
            ;;
        -a|--all)
            BUILD_ALL=true
            shift
            ;;
        -c|--clean)
            CLEAN_OUTPUT=true
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            HOSTS+=("$1")
            shift
            ;;
    esac
done

# Define all available hosts
ALL_HOSTS=(
    "caddy"
    "postgresql"
    "authentik"
    "nextcloud"
    "media"
    "monitoring"
    "guacamole"
    "vaultwarden"
    "dns"
    "mail"
)

# Function to list available hosts
list_hosts() {
    echo "Available hosts:"
    for host in "${ALL_HOSTS[@]}"; do
        echo "  - $host"
    done
    echo ""
    echo "Usage: $0 [HOSTS...] or $0 -a to build all"
}

# Function to clean output directory
clean_output() {
    if [[ "$CLEAN_OUTPUT" == true ]]; then
        print_status "Cleaning output directory: $OUTPUT_DIR"
        rm -rf "$OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
        print_success "Output directory cleaned"
    fi
}

# Function to build a single host
build_host() {
    local host="$1"
    local output_file="$OUTPUT_DIR/nixmox-${host}-lxc.tar.gz"
    
    print_status "Building $host host..."
    
    # Check if the host configuration exists
    if ! nix eval ".#nixosConfigurations.${host}" >/dev/null 2>&1; then
        print_error "Host configuration not found: $host"
        return 1
    fi
    
    # Build the LXC image
    print_status "Generating LXC image for $host..."
    nix build ".#packages.x86_64-linux.${host}" -o "$output_file"
    
    if [[ -f "$output_file" ]]; then
        print_success "Built $host: $output_file"
    else
        print_error "Failed to build $host"
        return 1
    fi
}

# Function to build all hosts
build_all_hosts() {
    print_status "Building all hosts..."
    
    local failed_hosts=()
    local successful_hosts=()
    
    for host in "${ALL_HOSTS[@]}"; do
        if build_host "$host"; then
            successful_hosts+=("$host")
        else
            failed_hosts+=("$host")
        fi
    done
    
    echo ""
    if [[ ${#successful_hosts[@]} -gt 0 ]]; then
        print_success "Successfully built ${#successful_hosts[@]} hosts:"
        for host in "${successful_hosts[@]}"; do
            echo "  ✓ $host"
        done
    fi
    
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        print_error "Failed to build ${#failed_hosts[@]} hosts:"
        for host in "${failed_hosts[@]}"; do
            echo "  ✗ $host"
        done
        exit 1
    fi
}

# Function to build specific hosts
build_specific_hosts() {
    print_status "Building specified hosts: ${HOSTS[*]}"
    
    local failed_hosts=()
    local successful_hosts=()
    
    for host in "${HOSTS[@]}"; do
        # Validate host name
        if [[ ! " ${ALL_HOSTS[*]} " =~ " ${host} " ]]; then
            print_error "Unknown host: $host"
            print_status "Available hosts: ${ALL_HOSTS[*]}"
            exit 1
        fi
        
        if build_host "$host"; then
            successful_hosts+=("$host")
        else
            failed_hosts+=("$host")
        fi
    done
    
    echo ""
    if [[ ${#successful_hosts[@]} -gt 0 ]]; then
        print_success "Successfully built ${#successful_hosts[@]} hosts:"
        for host in "${successful_hosts[@]}"; do
            echo "  ✓ $host"
        done
    fi
    
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        print_error "Failed to build ${#failed_hosts[@]} hosts:"
        for host in "${failed_hosts[@]}"; do
            echo "  ✗ $host"
        done
        exit 1
    fi
}

# Main execution
main() {
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Clean output if requested
    clean_output
    
    # List hosts if requested
    if [[ "$LIST_HOSTS" == true ]]; then
        list_hosts
        exit 0
    fi
    
    # Determine what to build
    if [[ "$BUILD_ALL" == true ]]; then
        build_all_hosts
    elif [[ ${#HOSTS[@]} -gt 0 ]]; then
        build_specific_hosts
    else
        print_warning "No hosts specified. Building all hosts..."
        build_all_hosts
    fi
    
    print_success "Image building completed!"
    print_status "Images are available in: $OUTPUT_DIR"
    print_status "Next step: Deploy to Proxmox using: just deploy-phase1 ENV=dev"
}

# Run main function
main "$@"
