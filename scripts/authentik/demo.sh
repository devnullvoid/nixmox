#!/usr/bin/env bash

# Demo script for Authentik Outpost Deployment Automation
# This script shows what the automation would do without actually running it

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/outpost-config.yaml"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Authentik Outpost Deployment Automation Demo${NC}"
echo "This script shows what the automation would do without actually running it."
echo ""

# Check if config file exists
if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${GREEN}✅ Configuration file found: $CONFIG_FILE${NC}"
else
    echo -e "${YELLOW}⚠️  Configuration file not found: $CONFIG_FILE${NC}"
fi

# Check if secrets file exists
if [[ -f "$PROJECT_ROOT/secrets/default.yaml" ]]; then
    echo -e "${GREEN}✅ Secrets file found: $PROJECT_ROOT/secrets/default.yaml${NC}"
else
    echo -e "${YELLOW}⚠️  Secrets file not found: $PROJECT_ROOT/secrets/default.yaml${NC}"
fi

# Check if Terraform directories exist
echo ""
echo -e "${BLUE}📁 Terraform Configuration Check:${NC}"
for outpost_type in ldap radius; do
    terraform_dir="$PROJECT_ROOT/terraform/authentik/$outpost_type"
    if [[ -d "$terraform_dir" ]]; then
        echo -e "  ${GREEN}✅ $outpost_type: $terraform_dir${NC}"
        
        # Check if main.tf exists
        if [[ -f "$terraform_dir/main.tf" ]]; then
            echo -e "    ${GREEN}  └─ main.tf found${NC}"
        else
            echo -e "    ${YELLOW}  └─ main.tf missing${NC}"
        fi
        
        # Check if terraform.tfvars exists
        if [[ -f "$terraform_dir/terraform.tfvars" ]]; then
            echo -e "    ${GREEN}  └─ terraform.tfvars found${NC}"
        else
            echo -e "    ${YELLOW}  └─ terraform.tfvars missing${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  $outpost_type: $terraform_dir (missing)${NC}"
    fi
done

# Check if deploy script exists
echo ""
echo -e "${BLUE}📜 Script Availability Check:${NC}"
if [[ -f "$SCRIPT_DIR/deploy-outposts.sh" ]]; then
    echo -e "  ${GREEN}✅ Main deployment script: deploy-outposts.sh${NC}"
else
    echo -e "  ${YELLOW}⚠️  Main deployment script: deploy-outposts.sh (missing)${NC}"
fi

if [[ -f "$SCRIPT_DIR/deploy.sh" ]]; then
    echo -e "  ${GREEN}✅ Quick deployment wrapper: deploy.sh${NC}"
else
    echo -e "  ${YELLOW}⚠️  Quick deployment wrapper: deploy.sh (missing)${NC}"
fi

# Check if deploy-nixos.sh exists
if [[ -f "$PROJECT_ROOT/scripts/deploy-nixos.sh" ]]; then
    echo -e "  ${GREEN}✅ NixOS deployment script: deploy-nixos.sh${NC}"
else
    echo -e "  ${YELLOW}⚠️  NixOS deployment script: deploy-nixos.sh (missing)${NC}"
fi

# Check required tools
echo ""
echo -e "${BLUE}🛠️  Required Tools Check:${NC}"
for tool in terraform sops ssh scp jq curl; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $tool: $(command -v $tool)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $tool: not found${NC}"
    fi
done

# Show what the automation would do
echo ""
echo -e "${BLUE}📋 What the Automation Would Do:${NC}"
echo "1. ${GREEN}🔍 Extract bootstrap token from SOPS-encrypted secrets${NC}"
echo "2. ${GREEN}🏗️  Deploy LDAP outpost using Terraform${NC}"
echo "3. ${GREEN}🏗️  Deploy Radius outpost using Terraform${NC}"
echo "4. ${GREEN}⏳ Wait for outposts to become ready via API${NC}"
echo "5. ${GREEN}🔑 Retrieve fresh outpost tokens from Authentik${NC}"
echo "6. ${GREEN}📝 Update secrets file with new tokens${NC}"
echo "7. ${GREEN}🔄 Redeploy Authentik with updated configuration${NC}"
echo "8. ${GREEN}✅ Verify all outpost services are running${NC}"

# Show configuration details
echo ""
echo -e "${BLUE}⚙️  Current Configuration:${NC}"
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Configuration file: $CONFIG_FILE"
    echo ""
    echo "Key settings:"
    echo "  - Authentik Host: $(grep -A 1 "host:" "$CONFIG_FILE" | grep "host:" | cut -d':' -f2 | tr -d ' "')"
    echo "  - Authentik Container: $(grep -A 2 "container:" "$CONFIG_FILE" | grep "container:" | cut -d':' -f2 | tr -d ' "')"
    echo "  - Authentik IP: $(grep -A 3 "ip:" "$CONFIG_FILE" | grep "ip:" | cut -d':' -f2 | tr -d ' "')"
    echo "  - Terraform Base Dir: $(grep -A 1 "base_dir:" "$CONFIG_FILE" | grep "base_dir:" | cut -d':' -f2 | tr -d ' "')"
else
    echo "No configuration file found - using defaults"
fi

# Show usage instructions
echo ""
echo -e "${BLUE}📖 Usage Instructions:${NC}"
echo "To run the full automation:"
echo "  ${GREEN}./scripts/authentik/deploy.sh${NC}"
echo ""
echo "To run with custom options:"
echo "  ${GREEN}./scripts/authentik/deploy-outposts.sh -v${NC}"
echo "  ${GREEN}./scripts/authentik/deploy-outposts.sh -c custom-config.yaml${NC}"
echo ""
echo "To see help:"
echo "  ${GREEN}./scripts/authentik/deploy-outposts.sh --help${NC}"

echo ""
echo -e "${GREEN}✨ Demo completed! The automation is ready to use.${NC}"
