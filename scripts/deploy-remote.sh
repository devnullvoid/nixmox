#!/usr/bin/env bash

set -euo pipefail

# NixMox Remote Deployment Script
# This script deploys NixMox configurations to existing NixOS containers

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
Usage: $0 [OPTIONS] CONTAINER_NAME REMOTE_HOST

Deploy NixMox configurations to existing NixOS containers.

OPTIONS:
    -h, --help          Show this help message
    -u, --user USER     SSH user (default: root)
    -p, --port PORT     SSH port (default: 22)
    -k, --key KEY       SSH private key file
    -d, --dry-run       Show what would be done without executing
    -l, --list          List available containers
    -t, --test          Test SSH connection only

CONTAINER_NAME:
    Name of the container to deploy (e.g., authentik, caddy, monitoring)

REMOTE_HOST:
    IP address or hostname of the remote NixOS container

Examples:
    $0 authentik 192.168.1.100                    # Deploy authentik to 192.168.1.100
    $0 -u nixmox -p 2222 caddy 192.168.1.101     # Deploy caddy with custom user/port
    $0 -k ~/.ssh/id_rsa monitoring 192.168.1.102 # Deploy with SSH key
    $0 -t authentik 192.168.1.100                 # Test SSH connection only
    $0 -l                                          # List available containers

Available containers:
    - authentik
    - caddy
    - monitoring
EOF
}

# Default values
SSH_USER="root"
SSH_PORT="22"
SSH_KEY=""
DRY_RUN=false
LIST_CONTAINERS=false
TEST_ONLY=false
CONTAINER_NAME=""
REMOTE_HOST=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -l|--list)
            LIST_CONTAINERS=true
            shift
            ;;
        -t|--test)
            TEST_ONLY=true
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
            elif [[ -z "$REMOTE_HOST" ]]; then
                REMOTE_HOST="$1"
            else
                print_error "Too many arguments"
                show_usage
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
    exit 0
fi

# Check if container name and remote host are provided
if [[ -z "$CONTAINER_NAME" ]]; then
    print_error "Container name is required"
    show_usage
    exit 1
fi

if [[ -z "$REMOTE_HOST" ]]; then
    print_error "Remote host is required"
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

# Build SSH command
SSH_CMD="ssh"
if [[ -n "$SSH_KEY" ]]; then
    SSH_CMD="$SSH_CMD -i $SSH_KEY"
fi
SSH_CMD="$SSH_CMD -p $SSH_PORT $SSH_USER@$REMOTE_HOST"

# Test SSH connection
print_status "Testing SSH connection to $REMOTE_HOST..."
if ! $SSH_CMD "echo 'SSH connection successful'" 2>/dev/null; then
    print_error "Failed to connect to $REMOTE_HOST"
    print_status "Please check:"
    echo "  - SSH service is running on the remote host"
    echo "  - SSH credentials are correct"
    echo "  - Network connectivity"
    echo "  - Firewall settings"
    exit 1
fi

print_success "SSH connection successful"

if [[ "$TEST_ONLY" == "true" ]]; then
    print_success "SSH test completed successfully"
    exit 0
fi

# Check if remote host is NixOS
print_status "Checking if remote host is NixOS..."
if ! $SSH_CMD "test -f /etc/nixos/configuration.nix" 2>/dev/null; then
    print_error "Remote host does not appear to be NixOS"
    print_status "This script is designed for NixOS containers only"
    exit 1
fi

print_success "Remote host is NixOS"

# Check if remote host has flakes enabled
print_status "Checking if flakes are enabled on remote host..."
if ! $SSH_CMD "nix --version" 2>/dev/null | grep -q "nix (Nix)"; then
    print_error "Nix is not available on remote host"
    exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
    print_status "DRY RUN - Would execute the following:"
    echo "  Copy flake files to: $REMOTE_HOST:/tmp/nixmox-deploy/"
    echo "  Run: nixos-rebuild switch --flake /tmp/nixmox-deploy#$CONTAINER_NAME"
    exit 0
fi

# Create temporary directory with only essential files
TEMP_DIR=$(mktemp -d)
NIXMOX_DIR="$TEMP_DIR/nixmox-deploy"

print_status "Preparing essential flake files..."

# Create minimal directory structure
mkdir -p "$NIXMOX_DIR/modules"

# Copy only essential files
cp "$PROJECT_ROOT/flake.nix" "$NIXMOX_DIR/"
cp "$PROJECT_ROOT/flake.lock" "$NIXMOX_DIR/"
cp -r "$PROJECT_ROOT/modules" "$NIXMOX_DIR/"
cp -r "$PROJECT_ROOT/secrets" "$NIXMOX_DIR/"
cp "$PROJECT_ROOT/.sops.yaml" "$NIXMOX_DIR/"

# Copy flake files to remote host
print_status "Copying essential flake files to $REMOTE_HOST..."
if [[ -n "$SSH_KEY" ]]; then
    scp -i "$SSH_KEY" -P "$SSH_PORT" -r "$NIXMOX_DIR" "$SSH_USER@$REMOTE_HOST:/tmp/"
else
    scp -P "$SSH_PORT" -r "$NIXMOX_DIR" "$SSH_USER@$REMOTE_HOST:/tmp/"
fi

# Clean up local temp files
rm -rf "$TEMP_DIR"

print_success "Flake files copied successfully"

# Build and switch on remote host
print_status "Building and switching to new configuration on remote host..."
$SSH_CMD "cd /tmp/nixmox-deploy && nixos-rebuild switch --flake .#$CONTAINER_NAME"

print_success "Deployment completed successfully!"

print_status "Next steps:"
echo "  1. SSH into the container: ssh $SSH_USER@$REMOTE_HOST"
echo "  2. Test the deployment:"
echo "     - systemctl status sshd"
echo "     - systemctl status postgresql  # (for authentik)"
echo "     - systemctl status redis       # (for authentik)"
echo "     - systemctl status caddy       # (for caddy)"
echo "     - systemctl status prometheus  # (for monitoring)"
echo "  3. Change default password: passwd nixmox"
echo "  4. Test SSH with new user: ssh nixmox@$REMOTE_HOST"

print_warning "Default credentials:"
echo "  User: nixmox"
echo "  Password: nixmox"
echo "  (Change these after first login!)" 