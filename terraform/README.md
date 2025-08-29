# NixMox Terraform Configuration

This directory contains the Terraform configuration for NixMox infrastructure and authentication management. The configuration has been simplified and separated into two distinct parts:

## Structure

```
terraform/
├── infrastructure/           # Proxmox LXC container management
│   ├── main.tf             # Infrastructure configuration
│   ├── terraform.tfvars.example
│   └── .terraform/         # Terraform state (auto-created)
├── authentik/               # Authentik resource management
│   ├── main.tf             # Authentik configuration
│   ├── terraform.tfvars.example
│   └── .terraform/         # Terraform state (auto-created)
├── modules/                 # Reusable Terraform modules
│   ├── proxmox-lxc/        # Proxmox LXC container module
│   └── authentik-manifest/ # Authentik resources module
├── terraform-manifest.nix   # Nix manifest reader for Terraform
├── deploy.sh                # Deployment script
└── README.md                # This file
```

## Configuration

### Infrastructure (Proxmox LXC)

Manages all LXC containers defined in the Nix manifest:

- Container creation and configuration
- Network setup
- Resource allocation
- NixOS provisioning

### Authentik

Manages all Authentik resources defined in the Nix manifest:

- OIDC applications
- LDAP and RADIUS outposts
- Authentication providers
- User flows and policies

## Usage

### Quick Start

1. **Copy example configuration files:**
   ```bash
   cd terraform/infrastructure
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   
   cd ../authentik
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Deploy infrastructure:**
   ```bash
   ./deploy.sh apply-infra
   ```

3. **Deploy Authentik resources:**
   ```bash
   ./deploy.sh apply-auth
   ```

### Deployment Script

The `deploy.sh` script provides a unified interface for managing both configurations:

```bash
# Plan changes
./deploy.sh plan-infra      # Plan infrastructure changes
./deploy.sh plan-auth       # Plan Authentik changes
./deploy.sh plan-all        # Plan both

# Apply changes
./deploy.sh apply-infra     # Apply infrastructure changes
./deploy.sh apply-auth      # Apply Authentik changes
./deploy.sh apply-all       # Apply both

# Import existing state
./deploy.sh import-infra    # Import existing Proxmox containers
./deploy.sh import-auth     # Import existing Authentik resources

# Destroy resources (use with caution)
./deploy.sh destroy-infra   # Destroy all infrastructure
./deploy.sh destroy-auth    # Destroy all Authentik resources
```

### Manual Terraform Commands

You can also run Terraform commands directly in each directory:

```bash
# Infrastructure
cd terraform/infrastructure
terraform init
terraform plan -var="secrets_file=../../secrets/default.yaml"
terraform apply -var="secrets_file=../../secrets/default.yaml"

# Authentik
cd terraform/authentik
terraform init
terraform plan -var="secrets_file=../../secrets/default.yaml"
terraform apply -var="secrets_file=../../secrets/default.yaml"
```

## State Management

Each configuration maintains its own Terraform state:

- **Infrastructure state**: `terraform/infrastructure/.terraform/terraform.tfstate`
- **Authentik state**: `terraform/authentik/.terraform/terraform.tfstate`

This separation allows you to:
- Manage infrastructure and authentication independently
- Apply changes to one without affecting the other
- Use different team members for different responsibilities
- Maintain cleaner state files

## Importing Existing Resources

To import existing Proxmox containers or Authentik resources:

1. **Identify existing resources** that should be managed by Terraform
2. **Use the import commands** to bring them under Terraform management
3. **Review the plan** to ensure the imported state matches expectations
4. **Apply the changes** to finalize the import

## Configuration Files

### terraform.tfvars

Create `terraform.tfvars` files in each directory with your configuration:

**infrastructure/terraform.tfvars:**
```hcl
secrets_file = "../../secrets/default.yaml"
# Or use individual variables:
# pm_api_url = "https://your-proxmox-host:8006/api2/json"
# pm_api_token_id = "your-token-id"
# pm_api_token_secret = "your-token-secret"
```

**authentik/terraform.tfvars:**
```hcl
secrets_file = "../../secrets/default.yaml"
```

## Dependencies

- **Infrastructure** must be deployed before **Authentik** (containers need to exist)
- Both configurations read from the same Nix manifest (`terraform-manifest.nix`)
- SOPS-encrypted secrets file provides sensitive configuration values

## Troubleshooting

### Common Issues

1. **State conflicts**: Ensure you're working in the correct directory
2. **Provider errors**: Check your credentials and network connectivity
3. **Manifest parsing**: Verify the Nix manifest is valid and accessible

### Debugging

- Use `--verbose` flag with deploy.sh for detailed output
- Check Terraform logs in each directory
- Verify SOPS decryption works correctly
- Ensure Nix can evaluate the manifest

## Migration from Old Structure

If you're migrating from the old phased deployment structure:

1. **Backup your existing state**: Copy `terraform.tfstate` files
2. **Initialize new configurations**: Run `terraform init` in each directory
3. **Import existing resources**: Use the import commands to bring existing resources under management
4. **Verify configuration**: Run plans to ensure everything looks correct
5. **Apply changes**: Deploy the new configuration

## Security Notes

- Never commit `terraform.tfvars` files with sensitive data
- Use SOPS-encrypted secrets files for sensitive configuration
- Keep Terraform state files secure and backed up
- Use least-privilege access for Proxmox and Authentik APIs
