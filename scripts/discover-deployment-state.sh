#!/usr/bin/env bash

# NixMox Deployment State Discovery Script
# This script discovers the current deployment state and generates deployment-state.json

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_PATH="$PROJECT_ROOT/nixos/service-manifest.nix"

# Manifest reading functions
get_service_ip() {
    local service="$1"

    # Try to get IP from core_services first, then from services
    local ip=$(nix eval -f "$MANIFEST_PATH" "core_services.$service.ip" --raw 2>/dev/null || \
                nix eval -f "$MANIFEST_PATH" "services.$service.ip" --raw 2>/dev/null)

    if [[ -z "$ip" ]]; then
        log_error "Could not find IP address for service: $service"
        return 1
    fi

    echo "$ip"
}

get_service_hostname() {
    local service="$1"

    # Try to get hostname from core_services first, then from services
    local hostname=$(nix eval -f "$MANIFEST_PATH" "core_services.$service.hostname" --raw 2>/dev/null || \
                     nix eval -f "$MANIFEST_PATH" "services.$service.hostname" --raw 2>/dev/null)

    if [[ -z "$hostname" ]]; then
        log_error "Could not find hostname for service: $service"
        return 1
    fi

    echo "$hostname"
}

get_service_vmid() {
    local service="$1"

    # Try to get VMID from core_services first, then from services
    local vmid=$(nix eval -f "$MANIFEST_PATH" "core_services.$service.vmid" --raw 2>/dev/null || \
                 nix eval -f "$MANIFEST_PATH" "services.$service.vmid" --raw 2>/dev/null)

    if [[ -z "$vmid" ]]; then
        log_error "Could not find VMID for service: $service"
        return 1
    fi

    echo "$vmid"
}

get_service_version() {
    local service="$1"

    # Try to get version from services (core services might not have versions)
    local version=$(nix eval -f "$MANIFEST_PATH" "services.$service.version" --raw 2>/dev/null || echo "1.0")

    echo "$version"
}

get_service_dependencies() {
    local service="$1"

    # Try to get dependencies from services (core_services don't have dependencies)
    local deps=$(nix eval -f "$MANIFEST_PATH" "services.$service.depends_on" --json 2>/dev/null || echo "[]")

    echo "$deps"
}

# Check if a service is healthy
is_service_healthy() {
    local service="$1"
    local service_ip

    if ! service_ip=$(get_service_ip "$service"); then
        return 1
    fi

    # Service-specific health checks
    case "$service" in
        "postgresql")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet postgresql" 2>/dev/null
            ;;
        "dns")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet unbound" 2>/dev/null
            ;;
        "caddy")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet caddy" 2>/dev/null
            ;;
        "authentik")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet authentik" 2>/dev/null
            ;;
        "vaultwarden")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "curl -f -s http://localhost:8080/alive > /dev/null" 2>/dev/null
            ;;
        "guacamole")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server" 2>/dev/null
            ;;
        "monitoring")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet prometheus && systemctl is-active --quiet grafana" 2>/dev/null
            ;;
        "nextcloud")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet nextcloud" 2>/dev/null
            ;;
        "media")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet jellyfin" 2>/dev/null
            ;;
        "mail")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "systemctl is-active --quiet postfix && systemctl is-active --quiet dovecot" 2>/dev/null
            ;;
        "openbao")
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "curl -f -s http://localhost:8200/v1/sys/health > /dev/null" 2>/dev/null
            ;;
        *)
            log_warning "Unknown service: $service, assuming healthy if reachable"
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$service_ip" "true" 2>/dev/null
            ;;
    esac
}

# Discover deployed services
discover_deployed_services() {
    log_info "🔍 Discovering deployed services..."

    local deployed_services="{}"
    local deployed_containers="{}"
    local deployed_nixos="{}"

    # Get all services from manifest
    local all_services
    all_services=$(nix eval -f "$MANIFEST_PATH" --json 'let core = core_services // {}; app = services // {}; in core // app' | jq -r 'keys[]')

    for service in $all_services; do
        log_info "Checking service: $service"

        local service_ip
        if ! service_ip=$(get_service_ip "$service"); then
            log_warning "Cannot determine IP for $service, skipping"
            continue
        fi

        local service_hostname
        if ! service_hostname=$(get_service_hostname "$service"); then
            log_warning "Cannot determine hostname for $service, skipping"
            continue
        fi

        local service_vmid
        if ! service_vmid=$(get_service_vmid "$service"); then
            log_warning "Cannot determine VMID for $service, skipping"
            continue
        fi

        local service_version
        service_version=$(get_service_version "$service")

        local service_deps
        service_deps=$(get_service_dependencies "$service")

        # Check if service is healthy (deployed and running)
        if is_service_healthy "$service"; then
            log_success "✅ $service is deployed and healthy"

            # Add to deployed services
            deployed_services=$(echo "$deployed_services" | jq --arg service "$service" --arg ip "$service_ip" --arg hostname "$service_hostname" --arg version "$service_version" --argjson deps "$service_deps" \
                '.[$service] = {
                    "deployed_at": "'$(date +%s)'",
                    "version": $version,
                    "depends_on": $deps,
                    "ip": $ip,
                    "hostname": $hostname
                }')

            # Add to deployed containers
            deployed_containers=$(echo "$deployed_containers" | jq --arg service "$service" --arg ip "$service_ip" --arg vmid "$service_vmid" \
                '.[$service] = {
                    "created_at": "'$(date +%s)'",
                    "ip": $ip,
                    "vmid": ($vmid | tonumber)
                }')

            # Add to deployed NixOS
            deployed_nixos=$(echo "$deployed_nixos" | jq --arg service "$service" --arg version "$service_version" \
                '.[$service] = {
                    "deployed_at": "'$(date +%s)'",
                    "version": $version
                }')
        else
            log_warning "❌ $service is not healthy or not deployed"
        fi
    done

    # Generate deployment state
    local deployment_state
    deployment_state=$(jq -n \
        --arg version "1.0" \
        --arg last_updated "$(date +%s)" \
        --argjson deployed_services "$deployed_services" \
        --argjson deployed_containers "$deployed_containers" \
        --argjson deployed_nixos "$deployed_nixos" \
        '{
            "version": $version,
            "last_updated": $last_updated,
            "deployed_services": $deployed_services,
            "terraform_state": {
                "containers": $deployed_containers,
                "authentik_resources": {}
            },
            "nixos_deployments": $deployed_nixos
        }')

    echo "$deployment_state"
}

# Main function
main() {
    log_info "🚀 NixMox Deployment State Discovery"
    log_info "======================================"

    # Check prerequisites
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for this script"
        exit 1
    fi

    if ! command -v ssh &> /dev/null; then
        log_error "ssh is required for this script"
        exit 1
    fi

    # Change to project root
    cd "$PROJECT_ROOT"

    # Discover deployment state
    local deployment_state
    deployment_state=$(discover_deployed_services)

    # Write to file
    echo "$deployment_state" > deployment-state.json

    log_success "✅ Deployment state discovered and saved to deployment-state.json"

    # Show summary
    echo ""
    log_info "📊 Deployment Summary:"
    echo "$deployment_state" | jq '.deployed_services | keys[]' | while read -r service; do
        echo "  ✅ $service"
    done

    local deployed_count
    deployed_count=$(echo "$deployment_state" | jq '.deployed_services | length')
    local total_services
    total_services=$(nix eval -f "$MANIFEST_PATH" --json 'let core = core_services // {}; app = services // {}; in (core // app) | length')

    log_info "📈 Progress: $deployed_count/$total_services services deployed"

    # Show next steps
    echo ""
    log_info "🎯 Next Steps:"
    echo "1. Review deployment-state.json"
    echo "2. Run incremental deployment: ./scripts/deploy-orchestrator.sh --incremental --only openbao"
    echo "3. Or deploy all missing services: ./scripts/deploy-orchestrator.sh --incremental"
}

# Run main function
main "$@"
