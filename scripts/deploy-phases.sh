#!/usr/bin/env bash
set -euo pipefail

# NixMox Phased Deployment Script
# This script handles the deployment of infrastructure in logical phases

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

Deploy NixMox infrastructure in phases.

OPTIONS:
    -e, --environment ENV    Environment to deploy to (dev, staging, prod)
    -p, --phase PHASE       Phase to deploy (1, 2, 3, 4)
    -a, --args ARGS         Additional arguments for terraform
    -h, --help              Show this help message

PHASES:
    1 - Infrastructure Foundation (Proxmox LXC containers)
    2 - Core Services (Caddy, PostgreSQL, DNS, Authentik)
    3 - Application Services (Nextcloud, Media, Monitoring, etc.)
    4 - Advanced Configuration (Authentik outposts, OAuth2)

EXAMPLES:
    $0 -e dev -p 1                    # Deploy Phase 1 to development
    $0 -e dev -p 2                    # Deploy Phase 2 to development
    $0 -e prod -p 4 -a "-var-file=prod.tfvars"  # Deploy Phase 4 to production
EOF
}

# Default values
ENVIRONMENT="dev"
PHASE="1"
ADDITIONAL_ARGS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--phase)
            PHASE="$2"
            shift 2
            ;;
        -a|--args)
            ADDITIONAL_ARGS="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or prod."
    exit 1
fi

# Validate phase
if [[ ! "$PHASE" =~ ^[1-4]$ ]]; then
    print_error "Invalid phase: $PHASE. Must be 1, 2, 3, or 4."
    exit 1
fi

# Set paths
TERRANIX_FILE="terranix/${ENVIRONMENT}.nix"
TF_DIR="terraform/environments/${ENVIRONMENT}"
PHASES_DIR="terraform/phases"

print_status "Deploying Phase $PHASE to $ENVIRONMENT environment"

# Function to render Terranix to Terraform
render_terranix() {
    print_status "Rendering Terranix configuration..."
    if [[ ! -f "$TERRANIX_FILE" ]]; then
        print_error "Terranix file not found: $TERRANIX_FILE"
        exit 1
    fi
    
    mkdir -p "$TF_DIR"
    nix run nixpkgs#terranix -- "$TERRANIX_FILE" > "$TF_DIR/main.tf.json"
    print_success "Rendered $TERRANIX_FILE -> $TF_DIR/main.tf.json"
}

# Function to run Terraform commands
run_terraform() {
    local cmd="$1"
    local args="$2"
    
    print_status "Running: terraform $cmd"
    cd "$TF_DIR"
    
    case "$cmd" in
        init)
            terraform init
            ;;
        plan)
            terraform plan $args
            ;;
        apply)
            terraform apply $args
            ;;
        destroy)
            terraform destroy $args
            ;;
        *)
            print_error "Unknown terraform command: $cmd"
            exit 1
            ;;
    esac
    
    cd "$PROJECT_ROOT"
}

# Function to deploy Phase 1: Infrastructure Foundation
deploy_phase1() {
    print_status "Deploying Phase 1: Infrastructure Foundation"
    print_status "This will create base Proxmox LXC containers"
    
    render_terranix
    
    # Check if we need to initialize
    if [[ ! -d "$TF_DIR/.terraform" ]]; then
        run_terraform "init"
    fi
    
    # Plan and apply
    run_terraform "plan" "$ADDITIONAL_ARGS"
    
    print_warning "Review the plan above. Press Enter to continue or Ctrl+C to abort..."
    read -r
    
    run_terraform "apply" "$ADDITIONAL_ARGS"
    
    print_success "Phase 1 deployment completed!"
    print_status "Base LXC containers are now running on Proxmox"
}

# Function to deploy Phase 2: Core Services
deploy_phase2() {
    print_status "Deploying Phase 2: Core Services"
    print_status "This will deploy NixOS configurations to the containers"
    
    # Check if Phase 1 is complete
    if [[ ! -f "$TF_DIR/terraform.tfstate" ]]; then
        print_error "Phase 1 must be completed first. Run: $0 -e $ENVIRONMENT -p 1"
        exit 1
    fi
    
    # Build NixOS images
    print_status "Building NixOS LXC images..."
    just build-images
    
    # Deploy core services using Colmena
    print_status "Deploying core services..."
    just colmena-apply-infra
    
    print_success "Phase 2 deployment completed!"
    print_status "Core services are now running on the containers"
}

# Function to deploy Phase 3: Application Services
deploy_phase3() {
    print_status "Deploying Phase 3: Application Services"
    print_status "This will deploy application services to the containers"
    
    # Check if Phase 2 is complete
    if ! just colmena-apply-infra >/dev/null 2>&1; then
        print_error "Phase 2 must be completed first. Run: $0 -e $ENVIRONMENT -p 2"
        exit 1
    fi
    
    # Deploy application services
    print_status "Deploying application services..."
    just colmena-apply-services
    
    print_success "Phase 3 deployment completed!"
    print_status "Application services are now running on the containers"
}

# Function to deploy Phase 4: Advanced Configuration
deploy_phase4() {
    print_status "Deploying Phase 4: Advanced Configuration"
    print_status "This will configure Authentik outposts and OAuth2 providers"
    
    # Check if Phase 3 is complete
    if ! just colmena-apply-services >/dev/null 2>&1; then
        print_error "Phase 3 must be completed first. Run: $0 -e $ENVIRONMENT -p 3"
        exit 1
    fi
    
    # Deploy advanced configuration
    print_status "Deploying advanced configuration..."
    just colmena-apply-auth
    
    print_success "Phase 4 deployment completed!"
    print_status "Advanced configuration is now active"
}

# Main deployment logic
case "$PHASE" in
    1)
        deploy_phase1
        ;;
    2)
        deploy_phase2
        ;;
    3)
        deploy_phase3
        ;;
    4)
        deploy_phase4
        ;;
    *)
        print_error "Unknown phase: $PHASE"
        exit 1
        ;;
esac

print_success "Phase $PHASE deployment completed successfully!"
print_status "Next steps:"
case "$PHASE" in
    1)
        echo "  - Run: $0 -e $ENVIRONMENT -p 2"
        echo "  - Or run: just deploy-phase2 ENV=$ENVIRONMENT"
        ;;
    2)
        echo "  - Run: $0 -e $ENVIRONMENT -p 3"
        echo "  - Or run: just deploy-phase3 ENV=$ENVIRONMENT"
        ;;
    3)
        echo "  - Run: $0 -e $ENVIRONMENT -p 4"
        echo "  - Or run: just deploy-phase4 ENV=$ENVIRONMENT"
        ;;
    4)
        echo "  - All phases completed!"
        echo "  - Run: just deployment-status ENV=$ENVIRONMENT"
        ;;
esac
