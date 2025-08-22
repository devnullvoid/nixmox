# NixMox Deployment Guide

## 🏗️ **Architecture Overview**

NixMox uses a **phased deployment approach** with Terraform and NixOS:

```
Phase 1: Infrastructure Foundation
├── PostgreSQL (VMID 902) - Database backend
├── Caddy (VMID 901) - Reverse proxy & load balancer  
├── DNS (VMID 904) - Internal DNS resolution

Phase 2: Core Services
├── Authentik (VMID 903) - Identity & access management
├── Vaultwarden (VMID 905) - Password manager
├── Nextcloud (VMID 906) - File storage
├── Guacamole (VMID 907) - Remote desktop gateway
├── Media (VMID 908) - Media server
├── Monitoring (VMID 909) - System monitoring
└── Mail (VMID 910) - Email services
```

## 🚀 **Quick Start Deployment**

### 1. **Prerequisites**
- Proxmox VE server running
- Terraform installed
- SOPS for secrets management
- SSH key configured in `nixos/modules/common/default.nix`

### 2. **Deploy Infrastructure (Phase 1)**
```bash
# From project root
just deploy-phase1 env=dev

# Or manually:
cd terraform/phases
terraform apply \
  -var="environment=dev" \
  -var="deployment_phase=1" \
  -var="secrets_file=../environments/dev/secrets.sops.yaml" \
  -auto-approve
```

### 3. **Deploy Core Services (Phase 2)**
```bash
just deploy-phase2 env=dev

# Or manually:
terraform apply \
  -var="environment=dev" \
  -var="deployment_phase=2" \
  -var="secrets_file=../environments/dev/secrets.sops.yaml" \
  -auto-approve
```

## 🔧 **Service Deployment**

### **NixOS Configuration Deployment**
After containers are running, deploy NixOS configurations:

```bash
# Deploy to specific service
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#caddy \
  --target-host root@caddy.nixmox.lan \
  --fast

# Deploy to all services
nix run nixpkgs#colmena -- apply-local
```

### **Service-Specific Deployment**
```bash
# Deploy Authentik (includes database setup)
just deploy-authentik

# Deploy with custom configuration
just deploy-authentik config=production
```

## 📁 **File Structure**

```
nixmox/
├── nixos/
│   ├── hosts/           # Host-specific configurations
│   ├── modules/         # Reusable NixOS modules
│   └── flake.nix        # NixOS flake configuration
├── terraform/
│   ├── phases/          # Phased deployment configuration
│   ├── modules/         # Terraform modules
│   └── environments/    # Environment-specific settings
├── scripts/             # Deployment scripts
└── Justfile            # Deployment commands
```

## 🔑 **Key Configuration Files**

### **Terraform Configuration**
- `terraform/phases/main.tf` - Main deployment configuration
- `terraform/environments/dev/secrets.sops.yaml` - Encrypted secrets
- `terraform/environments/dev/terraform.tfvars.example` - Configuration template

### **NixOS Configuration**
- `nixos/hosts/*.nix` - Host-specific configurations
- `nixos/modules/*/default.nix` - Service modules
- `nixos/modules/common/default.nix` - Common configuration (SSH, users)

## 🚨 **Troubleshooting**

### **Container Access Issues**
```bash
# Check container status
just deployment-status env=dev

# SSH to container
ssh root@caddy.nixmox.lan

# Access via Proxmox console
# Go to Proxmox UI → Container → Console
```

### **Deployment Failures**
```bash
# Check Terraform state
cd terraform/phases
terraform state list

# Destroy and recreate specific container
terraform destroy -target='module.lxc.proxmox_lxc.container["caddy"]'

# Redeploy phase
just deploy-phase1 env=dev
```

### **NixOS Configuration Issues**
```bash
# Check configuration syntax
nix run nixpkgs#nixos-rebuild -- build --flake .#caddy

# View generated configuration
nix run nixpkgs#nixos-rebuild -- build-vm --flake .#caddy
```

## 🔄 **Common Workflows**

### **Adding a New Service**
1. Add container definition to `terraform/phases/main.tf`
2. Create NixOS host configuration in `nixos/hosts/`
3. Create service module in `nixos/modules/`
4. Deploy container with Terraform
5. Deploy NixOS configuration

### **Updating Service Configuration**
1. Modify NixOS module
2. Deploy configuration: `nixos-rebuild switch --flake .#service`
3. Test service functionality

### **Infrastructure Changes**
1. Modify Terraform configuration
2. Plan changes: `terraform plan -var="environment=dev"`
3. Apply changes: `terraform apply -var="environment=dev"`

## 📝 **Notes**

- **DNS is in Phase 1** so containers can resolve each other's hostnames
- **SSH keys** are configured in `nixos/modules/common/default.nix`
- **Secrets** are managed with SOPS and stored in `secrets.sops.yaml`
- **Container networking** uses VLAN 99 with IP range 192.168.99.10-19
- **Hostname mapping** should be added to your local `/etc/hosts` file for development

## 🆘 **Getting Help**

- Check `just --list` for available commands
- Review Terraform logs for infrastructure issues
- Check NixOS logs: `journalctl -u service-name`
- Use Proxmox console for container access when SSH fails 