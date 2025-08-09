#!/usr/bin/env bash

set -euo pipefail

# Usage function
usage() {
    cat << EOF
Usage: $0 <configuration> [target-host]

Deploy a NixOS configuration using build-host and target-host method.

Arguments:
    configuration   The flake configuration to deploy (e.g., authentik, caddy, dns)
    target-host     Target host for deployment (default: root@192.168.88.194)

Environment variables:
    BUILD_HOST      Build host (default: localhost)
    MAX_JOBS        Maximum build jobs (default: 1)
    DEPLOY_TIMEOUT  Deployment timeout in seconds (default: 1800)
    SHOW_STATUS     Show service status after deployment (default: false)

Examples:
    $0 authentik
    $0 authentik root@192.168.88.200
    $0 caddy root@192.168.88.195
    BUILD_HOST=localhost MAX_JOBS=4 $0 dns root@192.168.88.196
EOF
}

# Check arguments
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

# Configuration
FLAKE_CONFIG="$1"
TARGET_HOST="${2:-${TARGET_HOST:-root@192.168.88.194}}"
BUILD_HOST="${BUILD_HOST:-localhost}"
MAX_JOBS="${MAX_JOBS:-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Check if we're in the right directory
if [[ ! -f "flake.nix" ]]; then
    error "flake.nix not found. Please run this script from the nixmox directory."
    exit 1
fi

# Check if target host is reachable
log "Testing connection to target host: $TARGET_HOST"
if ! ssh -o ConnectTimeout=5 "$TARGET_HOST" "echo 'Connection successful'" >/dev/null 2>&1; then
    error "Cannot connect to target host: $TARGET_HOST"
    exit 1
fi

success "Connection to target host successful"

# Ensure flake files are up to date on remote host
log "Syncing flake files to remote host..."
if ! scp -q flake.nix flake.lock .sops.yaml "$TARGET_HOST:/root/nixmox/"; then
    error "Failed to sync flake files to remote host"
    exit 1
fi

if ! scp -rq modules/ secrets/ "$TARGET_HOST:/root/nixmox/"; then
    error "Failed to sync modules and secrets to remote host"
    exit 1
fi

success "Flake files synced to remote host"

# Build and deploy
log "Starting deployment: Building locally, deploying to $TARGET_HOST"
log "Configuration: $FLAKE_CONFIG"
log "Build host: $BUILD_HOST"
log "Max jobs: $MAX_JOBS"

# Use timeout to prevent hanging
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-1800}" # 30 minutes default

if timeout "$DEPLOY_TIMEOUT" nix run nixpkgs#nixos-rebuild -- switch \
    --flake ".#$FLAKE_CONFIG" \
    --target-host "$TARGET_HOST" \
    --build-host "$BUILD_HOST" \
    --verbose \
    --max-jobs "$MAX_JOBS"; then
    
    success "Deployment completed successfully!"
    
    # Verify main service is running (try common service patterns)
    log "Verifying services..."
    
    # Try to find the main service for this configuration
    MAIN_SERVICE=""
    case "$FLAKE_CONFIG" in
        authentik)
            MAIN_SERVICE="authentik.service"
            RELATED_SERVICES="authentik-ldap.service authentik-radius.service authentik-proxy.service"
            ;;
        caddy)
            MAIN_SERVICE="caddy.service"
            ;;
        dns)
            MAIN_SERVICE="unbound.service"
            RELATED_SERVICES="blocky.service"
            ;;
        mail)
            MAIN_SERVICE="postfix.service"
            RELATED_SERVICES="dovecot2.service opendkim.service"
            ;;
        monitoring)
            MAIN_SERVICE="prometheus.service"
            RELATED_SERVICES="grafana.service alertmanager.service"
            ;;
        nextcloud)
            MAIN_SERVICE="phpfpm-nextcloud.service"
            RELATED_SERVICES="nginx.service redis-nextcloud.service"
            ;;
        vaultwarden)
            MAIN_SERVICE="vaultwarden.service"
            ;;
        media)
            MAIN_SERVICE="jellyfin.service"
            RELATED_SERVICES="sonarr.service radarr.service prowlarr.service"
            ;;
        *)
            # Generic check - try the configuration name as service
            MAIN_SERVICE="${FLAKE_CONFIG}.service"
            ;;
    esac
    
    # Check main service
    if [[ -n "$MAIN_SERVICE" ]]; then
        if ssh "$TARGET_HOST" "systemctl is-active $MAIN_SERVICE" >/dev/null 2>&1; then
            success "$MAIN_SERVICE is running"
        else
            warn "$MAIN_SERVICE may not be running"
        fi
    fi
    
    # Check related services if defined
    if [[ -n "${RELATED_SERVICES:-}" ]]; then
        for service in $RELATED_SERVICES; do
            if ssh "$TARGET_HOST" "systemctl is-active $service" >/dev/null 2>&1; then
                success "$service is running"
            else
                warn "$service may not be running"
            fi
        done
    fi
    
    log "Deployment verification complete"
    
else
    error "Deployment failed or timed out after $DEPLOY_TIMEOUT seconds"
    exit 1
fi

# Optional: Show service status
if [[ "${SHOW_STATUS:-}" == "true" ]]; then
    log "Service status:"
    STATUS_SERVICES="$MAIN_SERVICE"
    if [[ -n "${RELATED_SERVICES:-}" ]]; then
        STATUS_SERVICES="$STATUS_SERVICES $RELATED_SERVICES"
    fi
    ssh "$TARGET_HOST" "systemctl status $STATUS_SERVICES --no-pager" || true
fi

# Configuration-specific success messages
case "$FLAKE_CONFIG" in
    authentik)
        success "All done! Authentik should be available at http://$TARGET_HOST:9000"
        ;;
    caddy)
        success "All done! Caddy reverse proxy is deployed on $TARGET_HOST"
        ;;
    dns)
        success "All done! DNS services are running on $TARGET_HOST"
        ;;
    mail)
        success "All done! Mail server is deployed on $TARGET_HOST"
        ;;
    monitoring)
        success "All done! Monitoring stack is available on $TARGET_HOST"
        ;;
    nextcloud)
        success "All done! Nextcloud should be available via the configured domain on $TARGET_HOST"
        ;;
    vaultwarden)
        success "All done! Vaultwarden should be available via the configured domain on $TARGET_HOST"
        ;;
    media)
        success "All done! Media services are deployed on $TARGET_HOST"
        ;;
    *)
        success "All done! $FLAKE_CONFIG configuration deployed to $TARGET_HOST"
        ;;
esac