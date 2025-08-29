#!/bin/bash

# NixMox Terraform Deployment Script
# This script handles both infrastructure and authentik deployments

set -e

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
Usage: $0 [OPTIONS] COMMAND [TARGET]

Commands:
    plan-infra      Plan infrastructure changes (Proxmox LXC)
    apply-infra     Apply infrastructure changes
    plan-auth       Plan Authentik changes
    apply-auth      Apply Authentik changes
    plan-all        Plan both infrastructure and Authentik changes
    apply-all       Apply both infrastructure and Authentik changes
    import-infra    Import existing Proxmox LXC state
    import-auth     Import existing Authentik state
    destroy-infra   Destroy infrastructure (use with caution)
    destroy-auth    Destroy Authentik resources (use with caution)

Options:
    -h, --help      Show this help message
    -v, --verbose  Enable verbose output
    --secrets PATH Path to secrets file (default: ../secrets/default.yaml)

Examples:
    $0 plan-infra
    $0 apply-infra
    $0 plan-auth --secrets ../secrets/prod.yaml
    $0 apply-all

EOF
}

# Default values
VERBOSE=false
SECRETS_FILE="../secrets/default.yaml"
COMMAND=""
TARGET=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --secrets)
            SECRETS_FILE="$2"
            shift 2
            ;;
        plan-infra|apply-infra|plan-auth|apply-auth|plan-all|apply-all|import-infra|import-auth|destroy-infra|destroy-auth)
            COMMAND="$1"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if command is provided
if [[ -z "$COMMAND" ]]; then
    print_error "No command specified"
    show_usage
    exit 1
fi

# Check if secrets file exists
if [[ ! -f "$SECRETS_FILE" ]]; then
    print_error "Secrets file not found: $SECRETS_FILE"
    exit 1
fi

# Function to run terraform command
run_terraform() {
    local dir="$1"
    local action="$2"
    local extra_args="$3"
    
    print_status "Running Terraform $action in $dir"
    
    cd "$dir"
    
    # Initialize if needed
    if [[ ! -d ".terraform" ]]; then
        print_status "Initializing Terraform in $dir"
        terraform init
    fi
    
    # Run the command
    if [[ "$VERBOSE" == "true" ]]; then
        terraform $action -var="secrets_file=$SECRETS_FILE" $extra_args
    else
        terraform $action -var="secrets_file=$SECRETS_FILE" $extra_args
    fi
    
    cd - > /dev/null
}

# Function to import existing state
import_state() {
    local dir="$1"
    local resource_type="$2"
    
    print_status "Importing existing $resource_type state in $dir"
    
    cd "$dir"
    
    # Initialize if needed
    if [[ ! -d ".terraform" ]]; then
        print_status "Initializing Terraform in $dir"
        terraform init
    fi
    
    # Import existing state
    print_warning "This will import existing $resource_type resources into Terraform state"
    print_warning "Make sure to review the plan before applying"
    
    # For now, just show what would be imported
    print_status "Run 'terraform plan' to see what would be imported"
    
    cd - > /dev/null
}

# Main execution logic
case "$COMMAND" in
    plan-infra)
        run_terraform "infrastructure" "plan"
        ;;
    apply-infra)
        run_terraform "infrastructure" "apply"
        ;;
    plan-auth)
        run_terraform "authentik" "plan"
        ;;
    apply-auth)
        run_terraform "authentik" "apply"
        ;;
    plan-all)
        print_status "Planning infrastructure changes..."
        run_terraform "infrastructure" "plan"
        print_status "Planning Authentik changes..."
        run_terraform "authentik" "plan"
        ;;
    apply-all)
        print_status "Applying infrastructure changes..."
        run_terraform "infrastructure" "apply"
        print_status "Applying Authentik changes..."
        run_terraform "authentik" "apply"
        ;;
    import-infra)
        import_state "infrastructure" "Proxmox LXC containers"
        ;;
    import-auth)
        import_state "authentik" "Authentik resources"
        ;;
    destroy-infra)
        print_warning "This will destroy ALL infrastructure resources!"
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        if [[ "$confirm" == "yes" ]]; then
            run_terraform "infrastructure" "destroy" "-auto-approve"
        else
            print_status "Destroy cancelled"
        fi
        ;;
    destroy-auth)
        print_warning "This will destroy ALL Authentik resources!"
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        if [[ "$confirm" == "yes" ]]; then
            run_terraform "authentik" "destroy" "-auto-approve"
        else
            print_status "Destroy cancelled"
        fi
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

print_success "Command completed successfully"
