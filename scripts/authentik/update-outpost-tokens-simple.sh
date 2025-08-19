#!/usr/bin/env bash

set -euo pipefail

# Simple script to update Authentik outpost tokens following sops-nix convention
# Decrypt -> Edit -> Re-encrypt approach as per convention

# Configuration
AUTHENTIK_HOST="${AUTHENTIK_HOST:-https://auth.nixmox.lan}"
AUTHENTIK_ADMIN_TOKEN="${AUTHENTIK_ADMIN_TOKEN:-}"
LDAP_OUTPOST_ID="${LDAP_OUTPOST_ID:-}"
RADIUS_OUTPOST_ID="${RADIUS_OUTPOST_ID:-}"
SECRETS_FILE="${SECRETS_FILE:-/home/jon/Dev/github/nixmox/secrets/default.yaml}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --host HOST          Authentik host URL (default: https://auth.nixmox.lan)
    -t, --token TOKEN        Authentik admin API token
    -l, --ldap-id ID         LDAP outpost ID from Terraform output
    -r, --radius-id ID       RADIUS outpost ID from Terraform output
    -s, --secrets-file FILE  Path to encrypted secrets file (default: $SECRETS_FILE)
    --help                   Show this help message

Examples:
    # Update LDAP outpost token
    $0 -t "admin-token" -l "outpost-uuid"
    
    # Update RADIUS outpost token  
    $0 -t "admin-token" -r "outpost-uuid"

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            AUTHENTIK_HOST="$2"
            shift 2
            ;;
        -t|--token)
            AUTHENTIK_ADMIN_TOKEN="$2"
            shift 2
            ;;
        -l|--ldap-id)
            LDAP_OUTPOST_ID="$2"
            shift 2
            ;;
        -r|--radius-id)
            RADIUS_OUTPOST_ID="$2"
            shift 2
            ;;
        -s|--secrets-file)
            SECRETS_FILE="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$AUTHENTIK_ADMIN_TOKEN" ]]; then
    log_error "AUTHENTIK_ADMIN_TOKEN is required"
    usage
    exit 1
fi

# Function to get outpost token
get_outpost_token() {
    local outpost_id="$1"
    local outpost_name="$2"
    
    if [[ -z "$outpost_id" ]]; then
        log_warn "No $outpost_name outpost ID provided, skipping" >&2
        return 0
    fi
    
    log_info "Getting token for $outpost_name outpost (ID: $outpost_id)" >&2
    
    local api_url="$AUTHENTIK_HOST/api/v3/core/tokens/ak-outpost-$outpost_id-api/view_key/"
    
    # Query the API to get the outpost token
    local response
    if response=$(curl -k -s -H "Authorization: Bearer $AUTHENTIK_ADMIN_TOKEN" \
                          -H "Accept: application/json" \
                          "$api_url" 2>/dev/null); then
        
        # Extract the token from the response
        local token
        if token=$(echo "$response" | jq -r '.key // empty' 2>/dev/null); then
            if [[ -n "$token" && "$token" != "null" ]]; then
                log_info "Successfully retrieved $outpost_name outpost token" >&2
                echo "$token"
                return 0
            else
                log_error "Failed to extract token from response for $outpost_name outpost" >&2
                return 1
            fi
        else
            log_error "Failed to parse JSON response for $outpost_name outpost" >&2
            return 1
        fi
    else
        log_error "Failed to query API for $outpost_name outpost token" >&2
        return 1
    fi
}

# Function to update secrets file following sops-nix convention
update_secrets_file() {
    local outpost_type="$1"
    local token="$2"
    
    log_info "Updating secrets file for $outpost_type outpost using sops convention"
    
    # Create temporary files with .yaml extension so sops creation rules match
    local temp_decrypted=$(mktemp --tmpdir="$(dirname "$SECRETS_FILE")" "sops-temp-decrypted-XXXXXX.yaml")
    local temp_updated=$(mktemp --tmpdir="$(dirname "$SECRETS_FILE")" "sops-temp-updated-XXXXXX.yaml")
    
    # Step 1: Decrypt to separate file
    log_info "Decrypting secrets file..."
    if ! sops decrypt "$SECRETS_FILE" > "$temp_decrypted"; then
        log_error "Failed to decrypt secrets file"
        rm -f "$temp_decrypted" "$temp_updated"
        return 1
    fi
    
    # Step 2: Make manual changes
    log_info "Updating token in authentik-$outpost_type section..."
    local section_name="authentik-$outpost_type"
    
    if awk -v token="$token" -v section="$section_name" '
        BEGIN { in_section = 0; in_env_block = 0 }
        # Reset section when we hit a new top-level section
        /^[a-zA-Z]/ && !/^  / { in_section = 0; in_env_block = 0 }
        # Match the target section
        $0 ~ "^" section ":" { 
            in_section = 1; 
            print; 
            next 
        }
        # When in target section, look for env: | block
        in_section && /^    env: \|/ {
            in_env_block = 1;
            print;
            next
        }
        # When in env block of target section, update AUTHENTIK_TOKEN
        in_section && in_env_block && /^        AUTHENTIK_TOKEN=/ { 
            print "        AUTHENTIK_TOKEN=" token; 
            next 
        }
        # Exit env block when we see something that is not indented at env level
        in_env_block && !/^        / && !/^$/ {
            in_env_block = 0
        }
        { print }
    ' "$temp_decrypted" > "$temp_updated"; then
        log_info "Token updated successfully in decrypted file"
    else
        log_error "Failed to update token in decrypted file"
        rm -f "$temp_decrypted" "$temp_updated"
        return 1
    fi
    
    # Step 3: Verify the change
    if awk -v section="$section_name" -v token="$token" '
        BEGIN { in_section = 0; in_env_block = 0; found = 0 }
        /^[a-zA-Z]/ && !/^  / { in_section = 0; in_env_block = 0 }
        $0 ~ "^" section ":" { in_section = 1; next }
        in_section && /^    env: \|/ { in_env_block = 1; next }
        in_section && in_env_block && $0 ~ "AUTHENTIK_TOKEN=" token { found = 1; exit }
        in_env_block && !/^        / && !/^$/ { in_env_block = 0 }
        END { exit !found }
    ' "$temp_updated"; then
        log_info "Token update verified in $section_name section"
    else
        log_error "Token update verification failed"
        rm -f "$temp_decrypted" "$temp_updated"
        return 1
    fi
    
    # Step 4: Create backup
    local backup_file="$SECRETS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$SECRETS_FILE" "$backup_file"; then
        log_info "Created backup: $backup_file"
    else
        log_warn "Failed to create backup, proceeding anyway"
    fi
    
    # Step 5: Re-encrypt with sops (following convention)
    log_info "Re-encrypting updated file..."
    # Change to the project directory so sops can find .sops.yaml
    local project_dir="$(dirname "$SECRETS_FILE")"
    cd "$project_dir"
    
                # Sops works when encrypting from a file (not stdin), so save to temp file first
            # Use explicit config path to ensure sops can find the creation rules
            # Create encrypted temp file with .yaml extension to satisfy sops rules
            local temp_encrypted=$(mktemp --tmpdir="$(dirname "$SECRETS_FILE")" "sops-temp-encrypted-XXXXXX.yaml")
            if sops --config "$(dirname "$SECRETS_FILE")/../.sops.yaml" -e "$(basename "$temp_updated")" > "$(basename "$temp_encrypted")"; then
        log_info "Successfully re-encrypted secrets file"
        
        # Step 6: Verify the encrypted file
        if sops decrypt "$(basename "$temp_encrypted")" | awk -v section="$section_name" -v token="$token" '
            BEGIN { in_section = 0; in_env_block = 0; found = 0 }
            /^[a-zA-Z]/ && !/^  / { in_section = 0; in_env_block = 0 }
            $0 ~ "^" section ":" { in_section = 1; next }
            in_section && /^    env: \|/ { in_env_block = 1; next }
            in_section && in_env_block && $0 ~ "AUTHENTIK_TOKEN=" token { found = 1; exit }
            in_env_block && !/^        / && !/^$/ { in_env_block = 0 }
            END { exit !found }
        '; then
            log_info "Encrypted file verification successful"
            
                                # Step 7: Replace original file
                    if mv "$(basename "$temp_encrypted")" "$(basename "$SECRETS_FILE")"; then
                log_info "Successfully updated encrypted secrets file"
            else
                log_error "Failed to replace original secrets file"
                rm -f "$temp_decrypted" "$temp_updated"
                return 1
            fi
        else
            log_error "Encrypted file verification failed"
            rm -f "$temp_decrypted" "$temp_updated" "$SECRETS_FILE.new"
            return 1
        fi
    else
        log_error "Failed to re-encrypt secrets file"
        rm -f "$temp_decrypted" "$temp_updated" "$SECRETS_FILE.new"
        return 1
    fi
    
                # Clean up temporary files
            rm -f "$temp_decrypted" "$temp_updated" "$temp_encrypted"
}

# Main execution
main() {
    log_info "Starting outpost token update process"
    log_info "Authentik host: $AUTHENTIK_HOST"
    log_info "Secrets file: $SECRETS_FILE"
    
    # Check if required tools are available
    for tool in jq curl sops; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed. Please install $tool first."
            exit 1
        fi
    done
    log_info "All required tools are available"
    
    # Process LDAP outpost if ID is provided
    if [[ -n "$LDAP_OUTPOST_ID" ]]; then
        log_info "Processing LDAP outpost with ID: $LDAP_OUTPOST_ID"
        if ldap_token=$(get_outpost_token "$LDAP_OUTPOST_ID" "LDAP"); then
            log_info "LDAP token retrieved, updating secrets file..."
            update_secrets_file "ldap" "$ldap_token"
        else
            log_error "Failed to process LDAP outpost"
            exit 1
        fi
    fi
    
    # Process RADIUS outpost if ID is provided
    if [[ -n "$RADIUS_OUTPOST_ID" ]]; then
        log_info "Processing RADIUS outpost with ID: $RADIUS_OUTPOST_ID"
        if radius_token=$(get_outpost_token "$RADIUS_OUTPOST_ID" "RADIUS"); then
            log_info "RADIUS token retrieved, updating secrets file..."
            update_secrets_file "radius" "$radius_token"
        else
            log_error "Failed to process RADIUS outpost"
            exit 1
        fi
    fi
    
    log_info "Outpost token update process completed successfully"
}

# Run main function
main "$@"
