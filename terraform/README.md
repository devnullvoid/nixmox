# Manifest-Driven Terraform Configuration

This directory contains the Terraform configuration for the Nixmox project, now fully integrated with the service manifest system.

## 🏗️ **Architecture Overview**

The Terraform configuration is now **manifest-driven**, meaning all infrastructure specifications are derived from the central `service-manifest.nix` file rather than being hard-coded in Terraform.

### **Key Components**

1. **`terraform-manifest.nix`** - Nix manifest reader that generates Terraform-compatible data
2. **`main.tf`** - Main Terraform configuration that reads from the manifest
3. **`modules/proxmox-lxc/`** - Proxmox LXC container management module
4. **`modules/authentik/`** - Authentik identity provider configuration

## 🔄 **How It Works**

### **1. Manifest Reading**
```bash
# The manifest reader extracts data from service-manifest.nix
nix eval -f terraform/terraform-manifest.nix --json
```

### **2. Data Flow**
```
service-manifest.nix → terraform-manifest.nix → Terraform external data source → Infrastructure
```

### **3. Phase-Based Deployment**
- **Phase 1**: Infrastructure services (DNS, PostgreSQL, Caddy, Authentik)
- **Phase 2**: Core authentication (Authentik)
- **Phase 3**: Application services (Vaultwarden, Guacamole, etc.)

## 📋 **Usage Examples**

### **Basic Deployment (Phase 1)**
```bash
cd terraform
terraform init
terraform plan -var="pm_api_url=..." -var="pm_api_token_id=..." -var="pm_api_token_secret=..." -var="deployment_phase=1"
```

### **Full Deployment (All Phases)**
```bash
terraform plan -var="pm_api_url=..." -var="pm_api_token_id=..." -var="pm_api_token_secret=..." -var="deployment_phase=3"
```

### **Environment-Specific Deployment**
```bash
terraform plan -var="environment=prod" -var="deployment_phase=3" ...
```

## 🔧 **Configuration**

### **Required Variables**
- `pm_api_url` - Proxmox API endpoint
- `pm_api_token_id` - Proxmox API token ID
- `pm_api_token_secret` - Proxmox API token secret

### **Optional Variables**
- `environment` - Deployment environment (dev/staging/prod)
- `deployment_phase` - Which phase to deploy (1-3)
- `secrets_file` - Path to SOPS encrypted secrets file

### **SOPS Integration**
The configuration automatically reads from SOPS encrypted files when provided:
```bash
terraform plan -var="secrets_file=../secrets/default.yaml" ...
```

## 📊 **Manifest Data Structure**

The manifest reader provides the following data to Terraform:

### **Container Specifications**
```json
{
  "postgresql": {
    "vmid": 902,
    "hostname": "postgresql.nixmox.lan",
    "cores": 4,
    "memory": 4096,
    "disk_gb": 64,
    "ip": "192.168.99.11",
    "gw": "192.168.99.1",
    "vlan_tag": "99",
    "onboot": true,
    "start": true
  }
}
```

### **Network Configuration**
```json
{
  "dns_server": "192.168.99.13",
  "gateway": "192.168.99.1",
  "network_cidr": "192.168.99.0/24",
  "vlan_tag": 99,
  "domain": "nixmox.lan"
}
```

### **DNS Records**
```json
{
  "postgresql": {
    "domain": "postgresql.nixmox.lan",
    "ip": "192.168.99.11"
  }
}
```

## 🚀 **Benefits of Manifest-Driven Approach**

1. **Single Source of Truth** - All service specifications in one place
2. **Consistency** - NixOS and Terraform use identical data
3. **Maintainability** - Update manifest, both systems automatically update
4. **Validation** - Nix evaluation catches configuration errors early
5. **Flexibility** - Easy to add/remove services or change specifications

## 🔍 **Troubleshooting**

### **Manifest Reading Issues**
```bash
# Test manifest reader directly
nix eval -f terraform/terraform-manifest.nix --json

# Check for syntax errors in service-manifest.nix
nix eval -f nixos/service-manifest.nix --json
```

### **Terraform Issues**
```bash
# Reinitialize after changes
terraform init -reconfigure

# Check external data source
terraform console
> data.external.manifest.result
```

## 📁 **File Structure**

```
terraform/
├── README.md                 # This file
├── main.tf                   # Main manifest-driven configuration
├── terraform-manifest.nix    # Nix manifest reader for Terraform
├── terraform-manifest-full.nix # Full manifest reader (for reference)
├── modules/
│   ├── proxmox-lxc/         # Proxmox LXC container module
│   └── authentik/           # Authentik configuration module
├── environments/
│   └── dev/                 # Environment-specific configurations
└── legacy-phases/            # Legacy phase-based configuration (deprecated)
```

## 🔗 **Integration with NixOS**

This Terraform configuration works seamlessly with the NixOS host configurations:

1. **Terraform** creates the containers with the specifications from the manifest
2. **NixOS** configures the services using the same manifest data
3. **Orchestrator** coordinates both deployments using the manifest

## 🎯 **Next Steps**

- [ ] Add more Terraform modules for different service types
- [ ] Implement dynamic resource scaling based on environment
- [ ] Add monitoring and alerting infrastructure
- [ ] Integrate with CI/CD pipelines
