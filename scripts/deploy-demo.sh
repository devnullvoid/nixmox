#!/usr/bin/env bash

# NixMox Orchestrator Demo Script
# This script demonstrates the key features of our orchestrator

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_PATH="$PROJECT_ROOT/nixos/service-manifest.nix"

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

# Show demo banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                    NixMox Orchestrator Demo                 ║
║                                                              ║
║  This demo shows how the orchestrator works in practice    ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

# Demo 1: Manifest Validation
demo_manifest_validation() {
    log_info "Demo 1: Service Manifest Validation"
    echo "=========================================="
    
    if nix eval -f "$MANIFEST_PATH" --show-trace > /dev/null 2>&1; then
        log_success "✓ Manifest syntax is valid"
    else
        log_error "✗ Manifest validation failed"
        return 1
    fi
    
    # Show manifest structure
    echo ""
    echo "Manifest contains:"
    echo "  - Network configuration: $(nix eval -f "$MANIFEST_PATH" 'network.dns_server' --raw)"
    echo "  - Core services: $(nix eval -f "$MANIFEST_PATH" 'builtins.attrNames core_services' --raw | tr -d '[]' | tr ',' '\n' | sed 's/^/    /')"
    echo "  - Application services: $(nix eval -f "$MANIFEST_PATH" 'builtins.attrNames services' --raw | tr -d '[]' | tr ',' '\n' | sed 's/^/    /')"
    
    echo ""
}

# Demo 2: Dependency Analysis
demo_dependency_analysis() {
    log_info "Demo 2: Service Dependency Analysis"
    echo "======================================="
    
    echo "Service dependencies:"
    echo "  vaultwarden depends on: postgresql, caddy, authentik"
    echo "  guacamole depends on: postgresql, caddy, authentik"
    echo "  monitoring depends on: postgresql, caddy, authentik"
    echo ""
    
    echo "Deployment order (core services first):"
    echo "  1. postgresql (database)"
    echo "  2. dns (name resolution)"
    echo "  3. caddy (reverse proxy)"
    echo "  4. authentik (identity provider)"
    echo "  5. vaultwarden, guacamole, monitoring, etc."
    echo ""
}

# Demo 3: Health Check Generation
demo_health_checks() {
    log_info "Demo 3: Health Check Generation"
    echo "==================================="
    
    echo "Generated health checks for each service:"
    echo "  postgresql: systemctl is-active --quiet postgresql"
    echo "  caddy: systemctl is-active --quiet caddy"
    echo "  authentik: systemctl is-active --quiet authentik"
    echo "  vaultwarden: curl -f -s http://localhost:8080/alive"
    echo "  guacamole: systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server"
    echo ""
}

# Demo 4: Terraform Integration
demo_terraform_integration() {
    log_info "Demo 4: Terraform Integration"
    echo "================================="
    
    echo "Terraform configurations generated for each service:"
    echo "  - Workspace management (isolated per service)"
    echo "  - Variable files (.tfvars) from manifest"
    echo "  - Init, plan, and apply scripts"
    echo "  - Authentik resource creation (apps, providers, outposts)"
    echo ""
    
    echo "Example Terraform targets for vaultwarden:"
    echo "  - authentik_app (OIDC application)"
    echo "  - authentik_provider (OIDC provider)"
    echo "  - authentik_outpost (authentication endpoint)"
    echo ""
}

# Demo 5: Deployment Phases
demo_deployment_phases() {
    log_info "Demo 5: Deployment Phases"
    echo "============================="
    
    echo "The orchestrator follows this deployment order:"
    echo ""
    echo "Phase 1: tf:infra"
    echo "  - Provision Proxmox LXCs/VMs"
    echo "  - Configure networks and storage"
    echo "  - Set up base infrastructure"
    echo ""
    
    echo "Phase 2: nix:core"
    echo "  - Deploy core NixOS services"
    echo "  - Configure DNS, PostgreSQL, Caddy, Authentik"
    echo "  - Set up internal CA and certificates"
    echo ""
    
    echo "Phase 3: tf:auth-core"
    echo "  - Create Authentik outposts"
    echo "  - Configure core applications"
    echo "  - Set up authentication providers"
    echo ""
    
    echo "Phase 4: Per-service deployment"
    echo "  - For each service (vaultwarden, guacamole, etc.):"
    echo "    a. tf:service-infra (service-specific infrastructure)"
    echo "    b. nix:service-config (NixOS service configuration)"
    echo "    c. tf:service-config (Authentik resources)"
    echo "    d. verify (health checks and integration tests)"
    echo ""
}

# Demo 6: Practical Usage
demo_practical_usage() {
    log_info "Demo 6: Practical Usage"
    echo "=========================="
    
    echo "To use the orchestrator in practice:"
    echo ""
    echo "1. Define your services in the manifest:"
    echo "   - Edit nixos/service-manifest.nix"
    echo "   - Add new services with proper interfaces"
    echo "   - Define dependencies and health checks"
    echo ""
    
    echo "2. Deploy using the orchestrator script:"
    echo "   ./scripts/deploy-orchestrator.sh"
    echo ""
    
    echo "3. Monitor deployment progress:"
    echo "   nixmox-status"
    echo ""
    
    echo "4. Check individual service health:"
    echo "   /etc/nixmox-health-checks/<service>-health-check.sh"
    echo ""
    
    echo "5. View generated Terraform configs:"
    echo "   /etc/nixmox-terraform/<service>/"
    echo ""
}

# Demo 7: Benefits and Advantages
demo_benefits() {
    log_info "Demo 7: Benefits and Advantages"
    echo "==================================="
    
    echo "Key benefits of the NixMox orchestrator:"
    echo ""
    echo "✓ Declarative Configuration"
    echo "  - Infrastructure defined as code"
    echo "  - Version controlled and reproducible"
    echo "  - Easy to understand and modify"
    echo ""
    
    echo "✓ Dependency Management"
    echo "  - Automatic dependency resolution"
    echo "  - Correct deployment ordering"
    echo "  - No more manual dependency tracking"
    echo ""
    
    echo "✓ Health Monitoring"
    echo "  - Automatic health check generation"
    echo "  - Service status monitoring"
    echo "  - Early failure detection"
    echo ""
    
    echo "✓ Terraform Integration"
    echo "  - Authentik resource automation"
    echo "  - Service-specific infrastructure"
    echo "  - Workspace isolation"
    echo ""
    
    echo "✓ NixOS Integration"
    echo "  - Native NixOS module support"
    echo "  - Declarative service configuration"
    echo "  - Rollback and recovery capabilities"
    echo ""
}

# Main demo function
main() {
    show_banner
    echo ""
    
    demo_manifest_validation
    demo_dependency_analysis
    demo_health_checks
    demo_terraform_integration
    demo_deployment_phases
    demo_practical_usage
    demo_benefits
    
    echo ""
    log_success "Demo completed! The NixMox orchestrator is ready to use."
    echo ""
    echo "Next steps:"
    echo "  1. Review the service manifest: nixos/service-manifest.nix"
    echo "  2. Try the deployment script: ./scripts/deploy-orchestrator.sh"
    echo "  3. Check the integration example: examples/orchestrator-integration.nix"
    echo "  4. Read the usage guide: docs/orchestrator-usage.md"
    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output

Examples:
    $0                    # Run full demo
    $0 -v                # Run demo with verbose output

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main demo function
main "$@"
