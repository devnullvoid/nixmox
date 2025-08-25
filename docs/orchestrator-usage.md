# NixMox Orchestrator Usage Guide

This guide explains how to use the NixMox orchestrator to deploy and manage your infrastructure services.

## Overview

The NixMox orchestrator is a declarative deployment system that:
- Reads service manifests to understand your infrastructure
- Generates deployment plans with proper dependency ordering
- Coordinates Terraform and NixOS deployments
- Provides health monitoring and rollback capabilities
- Automates the deployment of complex multi-service architectures

## Quick Start

### 1. Define Your Service Manifest

Create a service manifest that describes your infrastructure:

```nix
# nixos/service-manifest.nix
{
  network = {
    dns_server = "192.168.99.13";
    gateway = "192.168.99.1";
    network_cidr = "192.168.99.0/24";
    vlan_tag = 99;
  };

  core_services = {
    postgresql = {
      enable = true;
      ip = "192.168.99.11";
      hostname = "postgresql.nixmox.lan";
      interface = {
        db = { name = "postgresql"; port = 5432; mode = "standalone"; };
        health = { startup = "systemctl is-active --quiet postgresql"; };
        proxy = { domain = "postgresql.nixmox.lan"; upstream = "localhost:5432"; };
      };
    };
    # ... other core services
  };

  services = {
    vaultwarden = {
      enable = true;
      ip = "192.168.99.14";
      hostname = "vaultwarden.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      interface = {
        auth = { type = "oidc"; provider = "authentik"; };
        proxy = { domain = "vaultwarden.nixmox.lan"; upstream = "localhost:8080"; };
        health = { liveness = "curl -f -s http://localhost:8080/alive"; };
      };
    };
    # ... other services
  };
}
```

### 2. Use the Orchestrator Library

Import and use the orchestrator in your NixOS configuration:

```nix
# In your NixOS configuration
{ lib, config, pkgs, ... }:

let
  nixmoxLib = import ./lib { inherit lib config pkgs; };
  manifest = import ./nixos/service-manifest.nix;
  
  # Generate deployment configuration
  deploymentConfig = nixmoxLib.utils.generateDeploymentConfig manifest;
in {
  # Use the generated configuration
  environment.etc."nixmox-deployment-plan.json" = {
    text = builtins.toJSON deploymentConfig.plan;
  };
}
```

### 3. Deploy Using the Script

Use the deployment script to orchestrate deployments:

```bash
# Deploy all services
./scripts/deploy-orchestrator.sh

# Deploy only a specific service and dependencies
./scripts/deploy-orchestrator.sh --service vaultwarden

# Show deployment plan without executing
./scripts/deploy-orchestrator.sh --dry-run
```

## Service Manifest Schema

### Network Configuration

```nix
network = {
  dns_server = "192.168.99.13";      # Primary DNS server IP
  gateway = "192.168.99.1";          # Network gateway IP
  network_cidr = "192.168.99.0/24";  # Network CIDR block
  vlan_tag = 99;                     # VLAN tag for the network
};
```

### Core Services

Core services are always deployed first and provide foundational infrastructure:

```nix
core_services = {
  service_name = {
    enable = true;                    # Whether to enable this service
    ip = "192.168.99.11";            # Static IP address
    hostname = "service.nixmox.lan"; # Fully qualified hostname
    
    interface = {
      # Terraform configuration
      terraform = {
        modules = [ "./terraform/service" ];
        variables = { domain = "nixmox.lan"; };
      };
      
      # Database configuration (if applicable)
      db = {
        name = "service_db";
        port = 5432;
        mode = "standalone";
      };
      
      # Proxy configuration
      proxy = {
        domain = "service.nixmox.lan";
        path = "/";
        upstream = "localhost:8080";
        tls = true;
        authz = false;
      };
      
      # Health check configuration
      health = {
        startup = "systemctl is-active --quiet service";
        liveness = "systemctl is-active --quiet service";
        interval = 30;
        timeout = 60;
        retries = 3;
      };
    };
  };
};
```

### Application Services

Application services depend on core services and provide user-facing functionality:

```nix
services = {
  app_name = {
    enable = true;
    ip = "192.168.99.20";
    hostname = "app.nixmox.lan";
    depends_on = [ "postgresql" "caddy" "authentik" ];
    ports = [ 8080 8443 ];
    
    interface = {
      # Terraform configuration for Authentik resources
      terraform = {
        modules = [ "./terraform/app" ];
        targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
        variables = {
          domain = "app.nixmox.lan";
          oidc_client_id = "app-oidc";
          oidc_scopes = [ "openid" "email" "profile" ];
        };
      };
      
      # OIDC authentication configuration
      auth = {
        type = "oidc";
        provider = "authentik";
        oidc = {
          redirect_uris = [ "https://app.nixmox.lan/oidc/callback" ];
          scopes = [ "openid" "email" "profile" ];
          username_claim = "preferred_username";
          groups_claim = "groups";
        };
      };
      
      # Proxy configuration
      proxy = {
        domain = "app.nixmox.lan";
        path = "/";
        upstream = "localhost:8080";
        tls = true;
        authz = true;
      };
      
      # Health check configuration
      health = {
        startup = "systemctl is-active --quiet app";
        liveness = "curl -f -s http://localhost:8080/health";
        interval = 30;
        timeout = 60;
        retries = 3;
      };
    };
  };
};
```

## Deployment Phases

The orchestrator follows a specific deployment order:

1. **tf:infra** - Core infrastructure provisioning (Proxmox LXCs, networks, storage)
2. **nix:core** - Core NixOS services deployment (dns, postgresql, caddy, authentik)
3. **tf:auth-core** - Authentik resources creation (outposts, core applications)
4. **Per-service deployment** - For each service:
   - **tf:service-infra** - Service-specific infrastructure
   - **nix:service-config** - NixOS service configuration
   - **tf:service-config** - Service-specific Terraform resources
   - **verify** - Health checks and integration tests

## Health Checks

Health checks are automatically generated for each service:

```bash
# Generated health check script example
#!/bin/bash
set -euo pipefail

# Startup check
if ! systemctl is-active --quiet vaultwarden; then
  echo "Vaultwarden startup check failed"
  exit 1
fi

# Liveness check
if ! curl -f -s http://localhost:8080/alive > /dev/null; then
  echo "Vaultwarden liveness check failed"
  exit 1
fi

echo "Vaultwarden is healthy"
```

## Terraform Integration

The orchestrator generates Terraform configurations for each service:

```bash
# Generated Terraform files
/etc/nixmox-terraform/
├── vaultwarden/
│   ├── terraform.tfvars      # Service variables
│   ├── init.sh              # Terraform init script
│   ├── plan.sh              # Terraform plan script
│   ├── apply.sh             # Terraform apply script
│   └── workspace.tf         # Workspace configuration
└── guacamole/
    ├── terraform.tfvars
    ├── init.sh
    ├── plan.sh
    ├── apply.sh
    └── workspace.tf
```

## Monitoring and Status

### Check Service Status

```bash
# Show overall status
nixmox-status

# Output example:
# NixMox Service Status
# =====================
# 
# Deployment Plan:
#   - tf_infra
#   - nix_core
#   - tf_auth_core
#   - guacamole
#   - vaultwarden
# 
# Service Health:
#   ✓ postgresql
#   ✓ dns
#   ✓ caddy
#   ✓ authentik
#   ✓ vaultwarden
#   ✓ guacamole
```

### Trigger Deployments

```bash
# Deploy all services
nixmox-deploy

# Deploy specific service
systemctl start nixmox-orchestrator
```

## Advanced Configuration

### Custom Health Checks

```nix
health = {
  startup = "systemctl is-active --quiet service";
  liveness = "curl -f -s http://localhost:8080/health";
  interval = 30;        # Check every 30 seconds
  timeout = 60;         # Health check timeout
  retries = 3;          # Number of retry attempts
};
```

### Custom Terraform Variables

```nix
terraform = {
  modules = [ "./terraform/service" ];
  targets = [ "authentik_app" "authentik_provider" ];
  variables = {
    domain = "service.nixmox.lan";
    oidc_client_id = "service-oidc";
    oidc_scopes = [ "openid" "email" "profile" ];
    custom_setting = "value";
  };
};
```

### Service Dependencies

```nix
services = {
  app = {
    depends_on = [ "postgresql" "caddy" "authentik" ];
    # ... other configuration
  };
};
```

## Troubleshooting

### Common Issues

1. **Service dependency failures**
   - Check that core services are healthy before deploying applications
   - Verify network connectivity between services

2. **Health check failures**
   - Review health check commands in the manifest
   - Check service logs for errors
   - Verify service is running and accessible

3. **Terraform errors**
   - Check Terraform workspace configuration
   - Verify Terraform variables and modules
   - Check Authentik API connectivity

### Debug Mode

Enable verbose output for debugging:

```bash
./scripts/deploy-orchestrator.sh -v
```

### Manual Health Checks

Run health checks manually:

```bash
# Check specific service
/etc/nixmox-health-checks/vaultwarden-health-check.sh

# Check all services
systemctl start nixmox-health-check
```

## Integration Examples

See `examples/orchestrator-integration.nix` for a complete example of integrating the orchestrator with NixOS.

## Next Steps

- [ ] Implement Terraform phase execution
- [ ] Add rollback functionality
- [ ] Implement service dependency validation
- [ ] Add monitoring and alerting
- [ ] Create web-based dashboard
