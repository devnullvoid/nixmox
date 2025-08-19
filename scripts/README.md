# NixMox Orchestration Scripts

This directory contains scripts for orchestrating the complete deployment workflow for NixMox modules.

## 🚀 Orchestration Scripts

### 1. `orchestrate-deployment.sh` - Full Deployment Workflow

**Purpose**: Complete end-to-end deployment from LXC creation to final configuration.

**Workflow**:
0. Deploy NixOS LXC to Proxmox via Terraform
1. Nix deploy module to LXC container
2. Run Terraform plans for module
3. Run secret update scripts for module
4. Nix deploy again to update secrets

**Usage**:
```bash
# Full deployment workflow
./scripts/orchestrate-deployment.sh authentik

# Dry run to see what would be done
./scripts/orchestrate-deployment.sh authentik --dry-run

# Skip LXC creation (assume container exists)
./scripts/orchestrate-deployment.sh authentik --skip-lxc

# Only run terraform deployment
./scripts/orchestrate-deployment.sh authentik --terraform-only

# Only run NixOS deployment
./scripts/orchestrate-deployment.sh authentik --nixos-only
```

**Use Cases**:
- Initial deployment of a new module
- Complete redeployment of existing infrastructure
- Testing deployment workflows

### 2. `update-module.sh` - Module Update Workflow

**Purpose**: Update existing modules with Terraform changes and secret updates.

**Workflow**:
1. Run Terraform plans for module
2. Run secret update scripts for module
3. Nix deploy again to update secrets

**Usage**:
```bash
# Full update workflow
./scripts/update-module.sh authentik

# Dry run to see what would be done
./scripts/update-module.sh authentik --dry-run

# Only run terraform deployment
./scripts/update-module.sh authentik --terraform-only

# Only run NixOS deployment
./scripts/update-module.sh authentik --nixos-only
```

**Use Cases**:
- Updating existing module configurations
- Applying Terraform changes
- Updating secrets and redeploying
- Quick configuration updates

## 🔧 Module-Specific Scripts

### Authentik Module

**Deployment Script**: `deploy-authentik.sh`
**Secret Update Scripts**:
- `update-ldap-token.sh` - Updates LDAP outpost tokens
- `update-radius-token.sh` - Updates RADIUS outpost tokens

**Workflow**:
1. Deploy NixOS configuration
2. Deploy LDAP and RADIUS outposts via Terraform
3. Fetch and update outpost tokens
4. Redeploy to apply updated secrets

### Other Modules

**Generic Deployment Script**: `deploy.sh`
- Supports all modules with generic deployment logic
- Automatically detects module type and runs appropriate services

## 🌍 Environment Variables

**Proxmox Configuration**:
- `PROXMOX_HOST` - Proxmox host for LXC creation
- `PROXMOX_USER` - Proxmox user (default: root)
- `PROXMOX_TOKEN` - Proxmox API token

**NixOS Deployment**:
- `BUILD_HOST` - Build host for NixOS deployment (default: localhost)
- `MAX_JOBS` - Maximum build jobs (default: 1)
- `TARGET_HOST` - Override target host (default: from terraform)

## 📋 Deployment Scenarios

### Scenario 1: New Module Deployment
```bash
# Deploy a new module from scratch
./scripts/orchestrate-deployment.sh caddy
```

### Scenario 2: Update Existing Module
```bash
# Update existing module with new configuration
./scripts/update-module.sh authentik
```

### Scenario 3: Terraform-Only Update
```bash
# Only update Terraform resources (e.g., new outposts)
./scripts/update-module.sh authentik --terraform-only
```

### Scenario 4: Secrets-Only Update
```bash
# Only update secrets and redeploy
./scripts/update-module.sh authentik --nixos-only
```

### Scenario 5: Skip LXC Creation
```bash
# Skip LXC creation (container already exists)
./scripts/orchestrate-deployment.sh authentik --skip-lxc
```

## 🔍 Troubleshooting

### Common Issues

1. **LXC Container Not Accessible**
   - Check if container exists on Proxmox
   - Verify network configuration
   - Use `--skip-lxc` if container already exists

2. **Terraform State Issues**
   - Ensure terraform directory is initialized
   - Check terraform.tfvars configuration
   - Verify provider configuration

3. **Secret Update Failures**
   - Check if update scripts exist for the module
   - Verify Authentik API access
   - Check sops configuration

4. **NixOS Deployment Failures**
   - Verify target host accessibility
   - Check flake configuration
   - Ensure required modules are available

### Debug Options

- Use `--dry-run` to see what would be executed
- Use `--verbose` for detailed logging
- Check individual script outputs for specific errors

## 📚 Examples

### Complete Authentik Deployment
```bash
# Full deployment workflow
./scripts/orchestrate-deployment.sh authentik

# This will:
# 1. Create LXC container on Proxmox
# 2. Deploy NixOS configuration
# 3. Deploy LDAP and RADIUS outposts
# 4. Update outpost tokens
# 5. Redeploy with updated secrets
```

### Quick Authentik Update
```bash
# Update existing configuration
./scripts/update-module.sh authentik

# This will:
# 1. Apply any Terraform changes
# 2. Update outpost tokens
# 3. Redeploy with updated secrets
```

### Module-Specific Deployment
```bash
# Use module-specific deployment script
./scripts/deploy-authentik.sh authentik

# Use generic deployment script
./scripts/deploy.sh authentik
```

## 🎯 Best Practices

1. **Always use dry-run first** for new deployments
2. **Test on staging environment** before production
3. **Keep terraform state** in version control
4. **Use specific target hosts** when possible
5. **Monitor deployment logs** for any issues
6. **Backup configurations** before major changes

## 🔄 Workflow Integration

These scripts can be integrated into:
- CI/CD pipelines
- Automated deployment workflows
- Infrastructure as Code processes
- Disaster recovery procedures

## 📝 Script Dependencies

**Required Tools**:
- `terraform` - Infrastructure deployment
- `nix` - NixOS configuration management
- `ssh` - Remote access
- `scp` - File transfer
- `jq` - JSON processing
- `sops` - Secret management

**Required Files**:
- `flake.nix` - NixOS configuration
- `modules/$MODULE/` - Module configuration
- `terraform/$MODULE/` - Terraform configuration
- `scripts/deploy-*.sh` - Deployment scripts
