# NixMox Deployment Guide

This guide explains how to deploy NixMox infrastructure using the integrated Terranix, Terraform, and phased deployment system.

## 🏗️ Architecture Overview

NixMox uses a **phased deployment approach** that separates infrastructure creation from service deployment:

- **Phase 1**: Create base Proxmox LXC containers
- **Phase 2**: Deploy NixOS configurations to containers
- **Phase 3**: Deploy application services
- **Phase 4**: Configure advanced features (Authentik outposts, OAuth2)

## 🚀 Quick Start

### Prerequisites

1. **Proxmox VE** running and accessible
2. **NixOS LXC template** available on Proxmox
3. **SSH access** to Proxmox node
4. **Network configuration** planned (IP ranges, gateway, etc.)

### 1. Configure Environment

Copy and customize the Terraform variables:

```bash
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
# Edit terraform.tfvars with your Proxmox details
```

### 2. Deploy Infrastructure

```bash
# Phase 1: Create base LXC containers
just deploy-phase1 ENV=dev

# Phase 2: Deploy NixOS configurations
just deploy-phase2 ENV=dev

# Phase 3: Deploy application services
just deploy-phase3 ENV=dev

# Phase 4: Configure advanced features
just deploy-phase4 ENV=dev
```

## 📋 Detailed Deployment Process

### Phase 1: Infrastructure Foundation

Creates base Proxmox LXC containers with minimal configuration:

- **Caddy** (10.10.0.10) - Reverse proxy and TLS termination
- **PostgreSQL** (10.10.0.11) - Database server
- **Authentik** (10.10.0.12) - Identity provider
- **DNS** (10.10.0.13) - DNS server (Unbound)

**Commands:**
```bash
# Plan the deployment
just tf-plan ENV=dev

# Apply the deployment
just deploy-phase1 ENV=dev
```

### Phase 2: Core Services

Deploys NixOS configurations to the containers:

1. **Build LXC images** from NixOS configurations
2. **Deploy core services** using Colmena
3. **Verify connectivity** between containers

**Commands:**
```bash
# Build all LXC images
just build-images

# Deploy core services
just deploy-phase2 ENV=dev
```

### Phase 3: Application Services

Deploys application services to the containers:

- Nextcloud, Media services, Monitoring, etc.
- Configures inter-service communication
- Sets up authentication flows

**Commands:**
```bash
just deploy-phase3 ENV=dev
```

### Phase 4: Advanced Configuration

Configures advanced features:

- Authentik OAuth2 providers
- Service integrations
- Production hardening

**Commands:**
```bash
just deploy-phase4 ENV=dev
```

## 🛠️ Available Commands

### Phased Deployment

```bash
just deploy-phase1 ENV=dev          # Deploy infrastructure
just deploy-phase2 ENV=dev          # Deploy core services
just deploy-phase3 ENV=dev          # Deploy applications
just deploy-phase4 ENV=dev          # Deploy advanced config
just deploy-all ENV=dev             # Deploy everything
```

### Image Building

```bash
just build-images                    # Build all LXC images
just build-host caddy               # Build specific host
just list-hosts                     # List available hosts
```

### Terraform Operations

```bash
just tf-init ENV=dev                # Initialize Terraform
just tf-plan ENV=dev                # Plan changes
just tf-apply ENV=dev               # Apply changes
just tf-destroy ENV=dev             # Destroy infrastructure
```

### Colmena Deployment

```bash
just colmena-apply-infra            # Deploy infrastructure
just colmena-apply-services         # Deploy application services
just colmena-apply-auth             # Deploy authentication
```

### Development and Testing

```bash
just test-configs                   # Test all NixOS configs
just validate-flake                 # Validate flake
just deployment-status ENV=dev      # Show deployment status
```

## 🔧 Configuration

### Environment-Specific Settings

Create environment-specific configurations:

```bash
# Development
cp terranix/dev.nix terranix/staging.nix
cp terranix/dev.nix terranix/prod.nix

# Customize each environment file
```

### Terraform Variables

Key variables to configure:

- `proxmox_url` - Proxmox API endpoint
- `proxmox_username` - Proxmox username
- `proxmox_password` - Proxmox password
- `network_gateway` - Network gateway IP
- `proxmox_node_name` - Target Proxmox node
- `nixos_template_id` - LXC template to use

### Network Configuration

Default network layout:

```
Network: 10.10.0.0/24
Gateway: 10.10.0.1
Caddy:   10.10.0.10
PostgreSQL: 10.10.0.11
Authentik: 10.10.0.12
DNS:     10.10.0.13
```

## 🔍 Troubleshooting

### Common Issues

1. **Terraform initialization fails**
   - Check Proxmox API connectivity
   - Verify credentials and permissions

2. **Container creation fails**
   - Check storage pool availability
   - Verify LXC template exists
   - Check network bridge configuration

3. **NixOS deployment fails**
   - Verify container connectivity
   - Check SSH key configuration
   - Review NixOS configuration syntax

### Debug Commands

```bash
# Check Terraform state
cd terraform/environments/dev
terraform show

# Validate NixOS configurations
just test-configs

# Check deployment status
just deployment-status ENV=dev

# View Terraform plan
just tf-plan ENV=dev
```

## 📚 Advanced Usage

### Custom Host Configurations

Add new hosts to the deployment:

1. **Create NixOS host configuration** in `nixos/hosts/`
2. **Add to Terranix configuration** in `terranix/proxmox-lxc.nix`
3. **Update build script** in `scripts/build-images.sh`
4. **Add to Colmena configuration** in `flake.nix`

### Multi-Environment Deployment

Deploy to different environments:

```bash
# Development
just deploy-phase1 ENV=dev

# Staging
just deploy-phase1 ENV=staging

# Production
just deploy-phase1 ENV=prod
```

### Custom Terraform Variables

Pass custom variables:

```bash
just deploy-phase1 ENV=dev -a "-var='container_cpus=4'"
```

## 🔐 Security Considerations

- **SSH keys**: Use strong SSH keys for container access
- **Passwords**: Change default passwords in production
- **Network**: Restrict container network access as needed
- **Secrets**: Use SOPS for sensitive configuration

## 📖 Next Steps

After successful deployment:

1. **Configure DNS** to point to your containers
2. **Set up SSL certificates** via Caddy
3. **Configure Authentik** OAuth2 providers
4. **Set up monitoring** and alerting
5. **Implement backup** strategies

## 🆘 Getting Help

- **Check logs**: Review Terraform and Colmena output
- **Validate configs**: Use `just test-configs`
- **Review state**: Check Terraform state files
- **Debug connectivity**: Test container network access

For more information, see the main [README.md](README.md) and [TESTING.md](TESTING.md). 