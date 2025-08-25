#!/usr/bin/env bash

# Smart deployment script with dependency resolution and health checks
# Handles intermittent network issues between VLANs (Sophos NGFW packet drops)

set -euo pipefail

# Configuration
MAX_RETRIES=3
RETRY_DELAY=5
SSH_TIMEOUT=30

# Color functions for better output
print_status() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Retry function for network operations
retry_operation() {
    local operation_name="$1"
    local max_attempts="${2:-$MAX_RETRIES}"
    local delay="${3:-$RETRY_DELAY}"
    local attempt=1
    
    print_status "Attempting $operation_name (max $max_attempts attempts)..."
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            print_success "$operation_name succeeded on attempt $attempt"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                print_warning "$operation_name failed on attempt $attempt, retrying in ${delay}s... (Sophos NGFW packet drop?)"
                sleep "$delay"
                # Exponential backoff
                delay=$((delay * 2))
            else
                print_error "$operation_name failed after $max_attempts attempts"
                return 1
            fi
        fi
        ((attempt++))
    done
}

# Retry SSH connection
retry_ssh() {
    local host="$1"
    local command="$2"
    local max_attempts="${3:-$MAX_RETRIES}"
    local attempt=1
    local delay="$RETRY_DELAY"
    
    while [ $attempt -le $max_attempts ]; do
        print_status "SSH attempt $attempt/$max_attempts to $host..."
        
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_TIMEOUT" "root@$host" "$command"; then
            print_success "SSH to $host succeeded on attempt $attempt"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                print_warning "SSH to $host failed on attempt $attempt, retrying in ${delay}s... (Sophos NGFW packet drop?)"
                sleep "$delay"
                delay=$((delay * 2))
            else
                print_error "SSH to $host failed after $max_attempts attempts"
                return 1
            fi
        fi
        ((attempt++))
    done
}

# Check SSH access with retry
check_ssh_access() {
    local host="$1"
    local ip="$2"
    
    print_status "Checking SSH access to $host ($ip)..."
    
    if retry_ssh "$ip" "echo 'SSH test successful'"; then
        print_success "SSH access to $host ($ip) confirmed"
        return 0
    else
        print_error "Cannot SSH to $host ($ip)"
        return 1
    fi
}

# Copy age key with retry
copy_age_key() {
    local host="$1"
    local ip="$2"
    
    print_status "Copying age key to $host ($ip)..."
    
    # Create age directory first
    if ! retry_ssh "$ip" "mkdir -p /root/.config/sops/age"; then
        print_error "Failed to create age directory on $host"
        return 1
    fi
    
    # Copy the key with retry
    local attempt=1
    local delay="$RETRY_DELAY"
    
    while [ $attempt -le $MAX_RETRIES ]; do
        print_status "SCP attempt $attempt/$MAX_RETRIES to $host..."
        
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_TIMEOUT" keys.txt "root@$ip:/root/.config/sops/age/"; then
            print_success "Age key copied to $host successfully"
            return 0
        else
            # Check if it's a path issue (don't retry) vs network issue (do retry)
            if [ $attempt -eq 1 ] && ! [ -f "keys.txt" ]; then
                print_error "keys.txt not found - this is a path issue, not a network issue"
                print_warning "Age key copy failed for $host - continuing with deployment"
                return 1
            fi
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                print_warning "SCP to $host failed on attempt $attempt, retrying in ${delay}s... (Sophos NGFW packet drop?)"
                sleep "$delay"
                delay=$((delay * 2))
            else
                print_warning "Age key copy failed for $host - continuing with deployment"
                return 1
            fi
        fi
        ((attempt++))
    done
}

# Check service health with retry
check_service_health() {
    local service="$1"
    local host="$2"
    
    case $service in
        "postgresql")
            retry_ssh "$host" "pg_isready -U postgres" >/dev/null 2>&1
            ;;
        "caddy")
            retry_ssh "$host" "systemctl is-active --quiet caddy.service" >/dev/null 2>&1
            ;;
        "guacamole")
            retry_ssh "$host" "systemctl is-active --quiet guacamole-server.service && systemctl is-active --quiet tomcat.service" >/dev/null 2>&1
            ;;
        *)
            retry_ssh "$host" "systemctl is-active --quiet $service.service" >/dev/null 2>&1
            ;;
    esac
}

# Wait for service to be healthy with retry
wait_for_service() {
    local service="$1"
    local host="$2"
    local max_wait=60
    local wait_time=0
    
    print_status "Waiting for $service to be healthy on $host..."
    
    while [ $wait_time -lt $max_wait ]; do
        if check_service_health "$service" "$host"; then
            print_success "$service is healthy on $host"
            return 0
        fi
        
        sleep 2
        wait_time=$((wait_time + 2))
        print_status "Still waiting for $service... (${wait_time}s elapsed)"
    done
    
    print_warning "$service health check timed out after ${max_wait}s"
    return 1
}

# Get target host for a service
get_target_host() {
    local service=$1
    case $service in
        "postgresql") echo "postgresql.nixmox.lan" ;;
        "caddy") echo "caddy.nixmox.lan" ;;
        "authentik") echo "authentik.nixmox.lan" ;;
        "guacamole") echo "guacamole.nixmox.lan" ;;
        "vaultwarden") echo "vaultwarden.nixmox.lan" ;;
        "nextcloud") echo "nextcloud.nixmox.lan" ;;
        "media") echo "media.nixmox.lan" ;;
        "monitoring") echo "monitoring.nixmox.lan" ;;
        "mail") echo "mail.nixmox.lan" ;;
        *) echo "unknown" ;;
    esac
}

# Function to deploy a single service with retry
deploy_service() {
    local service=$1
    print_status "Deploying $service..."
    
    local target_host
    target_host=$(get_target_host "$service")
    
    if [ "$target_host" = "unknown" ]; then
        print_error "Unknown service: $service"
        return 1
    fi
    
    # Get IP from hostname (you might want to make this more robust)
    local ip
    case $target_host in
        "postgresql.nixmox.lan") ip="192.168.99.11" ;;
        "caddy.nixmox.lan") ip="192.168.99.10" ;;
        "authentik.nixmox.lan") ip="192.168.99.12" ;;
        "guacamole.nixmox.lan") ip="192.168.99.16" ;;
        "vaultwarden.nixmox.lan") ip="192.168.99.13" ;;
        "nextcloud.nixmox.lan") ip="192.168.99.14" ;;
        "media.nixmox.lan") ip="192.168.99.15" ;;
        "monitoring.nixmox.lan") ip="192.168.99.17" ;;
        "mail.nixmox.lan") ip="192.168.99.18" ;;
        *) ip="unknown" ;;
    esac
    
    if [ "$ip" = "unknown" ]; then
        print_error "Unknown IP for service: $service"
        return 1
    fi
    
    print_status "Target host: $target_host"
    
    # Check SSH access with retry
    if ! check_ssh_access "$target_host" "$ip"; then
        print_error "Cannot SSH to $target_host"
        return 1
    fi
    
    # Copy age key with retry
    copy_age_key "$target_host" "$ip"
    
    # Deploy with retry
    print_status "Deploying NixOS configuration to $target_host..."
    
    local attempt=1
    local delay="$RETRY_DELAY"
    
    while [ $attempt -le $MAX_RETRIES ]; do
        print_status "Deploy attempt $attempt/$MAX_RETRIES to $target_host..."
        
        if ./scripts/deploy-nixos.sh "$service"; then
            print_success "Successfully deployed to $target_host"
            
            # Wait for service health with retry
            if wait_for_service "$service" "$ip"; then
                print_success "$service deployment completed successfully"
                return 0
            else
                print_warning "$service deployed but health check failed"
                return 1
            fi
        else
            if [ $attempt -lt $MAX_RETRIES ]; then
                print_warning "Deploy to $target_host failed on attempt $attempt, retrying in ${delay}s... (Sophos NGFW packet drop?)"
                sleep "$delay"
                delay=$((delay * 2))
            else
                print_error "Failed to deploy $service"
                return 1
            fi
        fi
        ((attempt++))
    done
}

# Function to deploy with dependencies
deploy_with_dependencies() {
    local target_service=$1
    print_status "Analyzing dependencies for $target_service..."
    
    local dependencies="${DEPENDENCIES[$target_service]:-}"
    if [ -n "$dependencies" ]; then
        print_status "Dependencies found: $dependencies"
        for dep in $dependencies; do
            print_status "Checking dependency: $dep"
            
            # Get dependency host info
            local dep_host
            dep_host=$(get_target_host "$dep")
            local dep_ip
            case $dep_host in
                "postgresql.nixmox.lan") dep_ip="192.168.99.11" ;;
                "caddy.nixmox.lan") dep_ip="192.168.99.10" ;;
                "authentik.nixmox.lan") dep_ip="192.168.99.12" ;;
                "guacamole.nixmox.lan") dep_ip="192.168.99.16" ;;
                "vaultwarden.nixmox.lan") dep_ip="192.168.99.13" ;;
                "nextcloud.nixmox.lan") dep_ip="192.168.99.14" ;;
                "media.nixmox.lan") dep_ip="192.168.99.15" ;;
                "monitoring.nixmox.lan") dep_ip="192.168.99.17" ;;
                "mail.nixmox.lan") dep_ip="192.168.99.18" ;;
                *) dep_ip="unknown" ;;
            esac
            
            # Check if dependency is already healthy
            if [ "$dep_ip" != "unknown" ] && check_service_health "$dep" "$dep_ip"; then
                print_success "Dependency $dep is already healthy, skipping deployment"
            else
                print_status "Deploying dependency: $dep"
                if ! deploy_service "$dep"; then
                    print_error "Failed to deploy dependency $dep, aborting"
                    return 1
                fi
            fi
        done
    else
        print_status "No dependencies found for $target_service"
    fi
    
    print_status "Deploying target service: $target_service"
    deploy_service "$target_service"
}

# Main function
main() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <service>"
        echo "Available services: ${!DEPENDENCIES[*]}"
        exit 1
    fi
    
    local target_service=$1
    
    if [[ ! -v DEPENDENCIES[$target_service] ]]; then
        print_error "Unknown service: $target_service"
        echo "Available services: ${!DEPENDENCIES[*]}"
        exit 1
    fi
    
    print_status "Starting smart deployment for $target_service"
    print_status "Note: Using retry logic for Sophos NGFW packet drop resilience"
    
    if deploy_with_dependencies "$target_service"; then
        print_success "Smart deployment completed successfully for $target_service"
        exit 0
    else
        print_error "Smart deployment failed for $target_service"
        exit 1
    fi
}

# Hardcoded dependency mapping
declare -A DEPENDENCIES=(
    ["postgresql"]=""
    ["caddy"]=""
    ["authentik"]="postgresql"
    ["guacamole"]="postgresql caddy"
    ["vaultwarden"]="caddy"
    ["nextcloud"]="postgresql caddy"
    ["media"]="postgresql caddy"
    ["monitoring"]="postgresql caddy"
    ["mail"]="postgresql caddy"
)

# Run main function
main "$@"
