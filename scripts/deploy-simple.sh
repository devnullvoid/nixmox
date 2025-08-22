#!/usr/bin/env bash

# NixMox Simple Deployment Script
# This script simplifies the deployment process by providing clear, step-by-step commands

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/phases"
SECRETS_FILE="$PROJECT_ROOT/terraform/environments/dev/secrets.sops.yaml"

# Default values
ENVIRONMENT="dev"
DEPLOYMENT_PHASE=""
AUTO_APPROVE=false

# Help function
show_help() {
    cat << EOF
NixMox Simple Deployment Script

Usage: $0 [OPTIONS] COMMAND

COMMANDS:
    status          Show deployment status
    plan           Show Terraform plan for current phase
    deploy         Deploy current phase
    destroy        Destroy current phase
    ssh            SSH to a container
    logs           Show container logs
    help           Show this help message

OPTIONS:
    -e, --env ENV          Environment (default: dev)
    -p, --phase PHASE      Deployment phase (1 or 2)
    -a, --auto-approve     Auto-approve Terraform changes
    -h, --help             Show this help message

EXAMPLES:
    # Show deployment status
    $0 status

    # Plan Phase 1 deployment
    $0 -p 1 plan

    # Deploy Phase 1 (infrastructure)
    $0 -p 1 deploy

    # Deploy Phase 2 (services)
    $0 -p 2 deploy

    # SSH to Caddy container
    $0 ssh caddy

    # Show Caddy logs
    $0 logs caddy

PHASES:
    Phase 1: Infrastructure (PostgreSQL, Caddy, DNS)
    Phase 2: Core Services (Authentik, Vaultwarden, Nextcloud, etc.)
EOF
}

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    
    if ! command -v sops &> /dev/null; then
        log_error "SOPS is not installed"
        exit 1
    fi
    
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "Secrets file not found: $SECRETS_FILE"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Change to Terraform directory
cd_terraform() {
    cd "$TERRAFORM_DIR"
}

# Get current phase from Terraform state
get_current_phase() {
    cd_terraform
    if terraform state list | grep -q "module.lxc.proxmox_lxc.container"; then
        # Check which containers exist to determine phase
        if terraform state list | grep -q "module.lxc.proxmox_lxc.container\[.*dns.*\]"; then
            echo "1"
        else
            echo "2"
        fi
    else
        echo "0"
    fi
}

# Show deployment status
show_status() {
    log_info "Checking deployment status..."
    cd_terraform
    
    local current_phase=$(get_current_phase)
    
    case $current_phase in
        0)
            log_warning "No containers deployed yet"
            ;;
        1)
            log_info "Phase 1 deployed (Infrastructure: PostgreSQL, Caddy, DNS)"
            log_info "Ready for Phase 2 deployment"
            ;;
        2)
            log_info "Phase 2 deployed (All services deployed)"
            log_success "Deployment complete!"
            ;;
    esac
    
    echo
    log_info "Container status:"
    terraform state list | grep "proxmox_lxc.container" | sed 's/.*\["\(.*\)"\].*/- \1/' || log_warning "No containers found"
}

# Show Terraform plan
show_plan() {
    if [[ -z "$DEPLOYMENT_PHASE" ]]; then
        log_error "Deployment phase must be specified with -p"
        exit 1
    fi
    
    log_info "Showing Terraform plan for Phase $DEPLOYMENT_PHASE..."
    cd_terraform
    
    terraform plan \
        -var="environment=$ENVIRONMENT" \
        -var="deployment_phase=$DEPLOYMENT_PHASE" \
        -var="secrets_file=$SECRETS_FILE"
}

# Deploy current phase
deploy_phase() {
    if [[ -z "$DEPLOYMENT_PHASE" ]]; then
        log_error "Deployment phase must be specified with -p"
        exit 1
    fi
    
    log_info "Deploying Phase $DEPLOYMENT_PHASE..."
    cd_terraform
    
    local apply_args=(
        -var="environment=$ENVIRONMENT"
        -var="deployment_phase=$DEPLOYMENT_PHASE"
        -var="secrets_file=$SECRETS_FILE"
    )
    
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        apply_args+=(-auto-approve)
    fi
    
    terraform apply "${apply_args[@]}"
    
    log_success "Phase $DEPLOYMENT_PHASE deployment completed!"
    
    # Show next steps
    case $DEPLOYMENT_PHASE in
        1)
            log_info "Next: Deploy Phase 2 with: $0 -p 2 deploy"
            ;;
        2)
            log_info "Next: Deploy NixOS configurations to containers"
            ;;
    esac
}

# Destroy current phase
destroy_phase() {
    if [[ -z "$DEPLOYMENT_PHASE" ]]; then
        log_error "Deployment phase must be specified with -p"
        exit 1
    fi
    
    log_warning "Destroying Phase $DEPLOYMENT_PHASE..."
    cd_terraform
    
    local destroy_args=(
        -var="environment=$ENVIRONMENT"
        -var="deployment_phase=$DEPLOYMENT_PHASE"
        -var="secrets_file=$SECRETS_FILE"
    )
    
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        destroy_args+=(-auto-approve)
    fi
    
    terraform destroy "${destroy_args[@]}"
    
    log_success "Phase $DEPLOYMENT_PHASE destroyed!"
}

# SSH to container
ssh_container() {
    local container_name="$1"
    if [[ -z "$container_name" ]]; then
        log_error "Container name must be specified"
        exit 1
    fi
    
    log_info "SSH to $container_name..."
    ssh "root@$container_name.nixmox.lan"
}

# Show container logs
show_logs() {
    local container_name="$1"
    if [[ -z "$container_name" ]]; then
        log_error "Container name must be specified"
        exit 1
    fi
    
    log_info "Showing logs for $container_name..."
    ssh "root@$container_name.nixmox.lan" "journalctl -f"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--phase)
            DEPLOYMENT_PHASE="$2"
            shift 2
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        status|plan|deploy|destroy|ssh|logs|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    case "${COMMAND:-}" in
        status)
            show_status
            ;;
        plan)
            show_plan
            ;;
        deploy)
            deploy_phase
            ;;
        destroy)
            destroy_phase
            ;;
        ssh)
            ssh_container "$1"
            ;;
        logs)
            show_logs "$1"
            ;;
        help)
            show_help
            ;;
        "")
            log_error "No command specified"
            show_help
            exit 1
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
