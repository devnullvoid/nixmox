# Authentik Outpost Deployment Automation

This directory contains automated scripts for deploying Authentik outposts, retrieving their tokens, and updating the secrets configuration.

## 🚀 Quick Start

For a complete automated deployment:

```bash
./scripts/authentik/deploy.sh
```

This will run the entire pipeline with confirmation prompts.

## 📋 What the Automation Does

The automated pipeline handles the complete process:

1. **Terraform Deployment**: Deploys LDAP and Radius outposts using Terraform
2. **Outpost Readiness**: Waits for outposts to become available via the Authentik API
3. **Token Retrieval**: Automatically fetches fresh outpost tokens from Authentik
4. **Secrets Update**: Updates the SOPS-encrypted secrets file with new tokens
5. **Configuration Deployment**: Redeploys Authentik with the updated configuration
6. **Service Verification**: Confirms all outpost services are running correctly

## 🛠️ Scripts Overview

### `deploy.sh` - Quick Deployment Wrapper
- Simple wrapper with confirmation prompts
- Runs the full automated pipeline
- Good for one-off deployments

### `deploy-outposts.sh` - Main Automation Script
- Full-featured automation script
- Configurable via `outpost-config.yaml`
- Command-line options for customization
- Comprehensive error handling and logging

### `automated-outpost-deployment.sh` - Legacy Script
- Original comprehensive script
- Maintained for backward compatibility

## ⚙️ Configuration

### `outpost-config.yaml`
The main configuration file controls all aspects of the deployment:

```yaml
# Authentik connection settings
authentik:
  host: "https://auth.nixmox.lan"
  container: "authentik"
  ip: "192.168.99.12"
  bootstrap_token_env: "AUTHENTIK_BOOTSTRAP_TOKEN"

# Terraform settings
terraform:
  base_dir: "terraform/authentik"
  outpost_types:
    - "ldap"
    - "radius"

# Secrets management
secrets:
  encrypted_file: "secrets/default.yaml"
  decrypted_file: "secrets/default.decrypted.yaml"
  backup_dir: "secrets/backups"

# Deployment settings
deployment:
  max_wait_attempts: 30
  wait_interval_seconds: 10
  service_verification_attempts: 20
  service_verification_interval_seconds: 15
```

## 🔧 Usage Options

### Basic Usage
```bash
# Run with default configuration
./scripts/authentik/deploy-outposts.sh

# Run with custom config file
./scripts/authentik/deploy-outposts.sh -c custom-config.yaml

# Enable verbose logging
./scripts/authentik/deploy-outposts.sh -v

# Show help
./scripts/authentik/deploy-outposts.sh -h
```

### Command Line Options
- `-h, --help`: Show help message
- `-c, --config`: Use custom configuration file
- `-v, --verbose`: Enable verbose logging with `set -x`

## 📁 File Structure

```
scripts/authentik/
├── README.md                           # This documentation
├── deploy.sh                           # Quick deployment wrapper
├── deploy-outposts.sh                  # Main automation script
├── automated-outpost-deployment.sh     # Legacy comprehensive script
├── outpost-config.yaml                 # Configuration file
├── update-outpost-tokens-simple.sh     # Manual token update script
└── get_outpost_tokens.sh              # Legacy token retrieval script
```

## 🔐 Prerequisites

The automation requires these tools to be available:

- **terraform**: For infrastructure deployment
- **sops**: For secrets management
- **ssh/scp**: For remote host access
- **jq**: For JSON processing
- **curl**: For API communication

## 🚨 Important Notes

### Bootstrap Token
- The script automatically extracts the bootstrap token from your SOPS-encrypted secrets
- Ensure `AUTHENTIK_BOOTSTRAP_TOKEN` is set in your secrets file
- The token must be valid and have API access permissions

### Network Access
- The script connects to `https://auth.nixmox.lan` for API operations
- Ensure the host running the script can reach this endpoint
- SSH access to the Authentik container IP is required for deployment

### Secrets Management
- The script creates automatic backups before updating secrets
- Backup files are named with timestamps: `default.yaml.backup.YYYYMMDD_HHMMSS`
- The decrypted secrets file (`default.decrypted.yaml`) is used temporarily

## 🔍 Troubleshooting

### Common Issues

1. **"Missing required tools"**
   - Install missing tools: `terraform`, `sops`, `ssh`, `scp`, `jq`
   - Ensure they're in your PATH

2. **"Failed to decrypt secrets file"**
   - Check that your SOPS age key is available
   - Verify the secrets file path is correct

3. **"Outpost did not become ready"**
   - Check Authentik service status
   - Verify network connectivity to the API endpoint
   - Check Authentik logs for errors

4. **"Failed to retrieve token"**
   - Ensure the bootstrap token has API access
   - Check that the outpost was created successfully
   - Verify the outpost ID format

### Debug Mode
Enable verbose logging to see detailed execution:

```bash
./scripts/authentik/deploy-outposts.sh -v
```

### Manual Steps
If automation fails, you can run steps manually:

1. **Deploy outposts**: `cd terraform/authentik/ldap && terraform apply`
2. **Get tokens**: Use the API or web UI
3. **Update secrets**: Edit `secrets/default.decrypted.yaml` and re-encrypt
4. **Redeploy**: `./scripts/deploy-nixos.sh authentik`

## 🔄 Workflow Integration

### CI/CD Pipeline
The automation can be integrated into CI/CD pipelines:

```bash
# Non-interactive deployment
./scripts/authentik/deploy-outposts.sh -c ci-config.yaml
```

### Scheduled Updates
For regular token rotation:

```bash
# Add to crontab for weekly updates
0 2 * * 0 /path/to/nixmox/scripts/authentik/deploy-outposts.sh
```

## 📝 Logging

The script provides comprehensive logging:

- **INFO**: General progress information
- **SUCCESS**: Successful operations
- **WARNING**: Non-critical issues
- **ERROR**: Critical failures

All operations are logged with timestamps and clear status indicators.

## 🤝 Contributing

When modifying the automation:

1. Update the configuration file for new settings
2. Add appropriate error handling
3. Update this documentation
4. Test with both success and failure scenarios
5. Maintain backward compatibility where possible

## 📚 Related Documentation

- [Authentik Outpost Documentation](https://goauthentik.io/docs/outposts/)
- [Terraform Authentik Provider](https://registry.terraform.io/providers/goauthentik/authentik)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [NixOS Deployment Guide](../README.md)
