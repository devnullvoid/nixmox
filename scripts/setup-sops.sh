#!/usr/bin/env bash

set -euo pipefail

# NixMox SOPS Setup Script
# This script helps set up SOPS with age keys for encrypted secrets

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
Usage: $0 [OPTIONS]

Set up SOPS with age keys for NixMox secrets management.

OPTIONS:
    -h, --help          Show this help message
    -g, --generate      Generate new age keys
    -e, --encrypt       Encrypt secrets file
    -d, --decrypt       Decrypt secrets file (for editing)
    -s, --setup         Complete setup (generate keys + encrypt)

Examples:
    $0 -g                    # Generate new age keys
    $0 -e                    # Encrypt secrets/default.yaml
    $0 -d                    # Decrypt secrets/default.yaml for editing
    $0 -s                    # Complete setup
EOF
}

# Default values
GENERATE_KEYS=false
ENCRYPT_FILE=false
DECRYPT_FILE=false
COMPLETE_SETUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -g|--generate)
            GENERATE_KEYS=true
            shift
            ;;
        -e|--encrypt)
            ENCRYPT_FILE=true
            shift
            ;;
        -d|--decrypt)
            DECRYPT_FILE=true
            shift
            ;;
        -s|--setup)
            COMPLETE_SETUP=true
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            print_error "Unknown argument: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if no options provided
if [[ "$GENERATE_KEYS" == "false" && "$ENCRYPT_FILE" == "false" && "$DECRYPT_FILE" == "false" && "$COMPLETE_SETUP" == "false" ]]; then
    print_error "No action specified"
    show_usage
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v sops &> /dev/null; then
        print_error "SOPS is not installed"
        print_status "Install with: nix-env -iA nixpkgs.sops"
        exit 1
    fi
    
    if ! command -v age-keygen &> /dev/null; then
        print_error "age is not installed"
        print_status "Install with: nix-env -iA nixpkgs.age"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Generate age keys
generate_keys() {
    print_status "Generating age keys..."
    
    # Create directory
    mkdir -p ~/.config/sops/age
    
    # Generate key
    age-keygen -o ~/.config/sops/age/keys.txt
    
    # Set permissions
    chmod 600 ~/.config/sops/age/keys.txt
    
    # Display public key
    print_success "Age keys generated successfully"
    print_status "Public key:"
    cat ~/.config/sops/age/keys.txt | grep "public key"
    
    print_warning "Add this public key to .sops.yaml"
}

# Create .sops.yaml
create_sops_config() {
    print_status "Creating .sops.yaml..."
    
    # Get public key
    PUBLIC_KEY=$(cat ~/.config/sops/age/keys.txt | grep "public key" | cut -d' ' -f4)
    
    # Create .sops.yaml
    cat > .sops.yaml << EOF
creation_rules:
  - path_regex: \.yaml$
    age: >-
      ${PUBLIC_KEY}
EOF
    
    print_success ".sops.yaml created with your public key"
}

# Encrypt secrets file
encrypt_file() {
    print_status "Encrypting secrets file..."
    
    if [[ ! -f "secrets/default.yaml" ]]; then
        print_error "secrets/default.yaml not found"
        exit 1
    fi
    
    if [[ ! -f ".sops.yaml" ]]; then
        print_error ".sops.yaml not found"
        print_status "Run with -g to generate keys and create .sops.yaml"
        exit 1
    fi
    
    sops -e -i secrets/default.yaml
    
    print_success "secrets/default.yaml encrypted successfully"
}

# Decrypt secrets file
decrypt_file() {
    print_status "Decrypting secrets file..."
    
    if [[ ! -f "secrets/default.yaml" ]]; then
        print_error "secrets/default.yaml not found"
        exit 1
    fi
    
    sops -d -i secrets/default.yaml
    
    print_success "secrets/default.yaml decrypted for editing"
    print_warning "Remember to re-encrypt with: $0 -e"
}

# Complete setup
complete_setup() {
    print_status "Starting complete SOPS setup..."
    
    check_prerequisites
    generate_keys
    create_sops_config
    encrypt_file
    
    print_success "SOPS setup completed successfully!"
    print_status "Next steps:"
    echo "  1. Add your SSH public keys to secrets/default.yaml"
    echo "  2. Add your service passwords and tokens"
    echo "  3. Re-encrypt: $0 -e"
    echo "  4. Deploy: ./scripts/deploy-remote.sh authentik YOUR_IP"
}

# Main execution
if [[ "$COMPLETE_SETUP" == "true" ]]; then
    complete_setup
elif [[ "$GENERATE_KEYS" == "true" ]]; then
    check_prerequisites
    generate_keys
    create_sops_config
elif [[ "$ENCRYPT_FILE" == "true" ]]; then
    check_prerequisites
    encrypt_file
elif [[ "$DECRYPT_FILE" == "true" ]]; then
    check_prerequisites
    decrypt_file
fi 