# NixMox Architecture: Manifest-Driven Infrastructure

## **Core Concept: "Manifest-Driven Infrastructure with NixOS and Terraform"**

NixMox is a **manifest-driven infrastructure platform** that uses NixOS LXC containers on Proxmox, where the service manifest and SOPS secrets are the **single sources of truth**. The orchestrator reads these sources and generates all Terraform and NixOS configurations dynamically.

## **Architecture Overview**

```
Service Manifest + SOPS Secrets → Orchestrator → Generated Configs → Deployment
     ↓                    ↓              ↓              ↓
Declarative Specs → Manifest Parser → Terraform/NixOS → Infrastructure
```

### **Key Components:**

1. **Service Manifest** (`service-manifest.nix`): Declarative specification of all services, their dependencies, and requirements
2. **SOPS Secrets**: Encrypted configuration values (passwords, tokens, sensitive data)
3. **Orchestrator**: Reads manifest + secrets, generates configurations, manages deployment lifecycle
4. **Generated Configs**: Terraform and NixOS configurations created from manifest values
5. **Deployment Engine**: Handles ordering, health checks, and incremental updates

## **Manifest-Driven Architecture Principles**

### **1. Single Source of Truth**
- **Service Manifest**: Defines service specifications, IPs, ports, dependencies, and requirements
- **SOPS Secrets**: Provides encrypted sensitive values (passwords, API keys, certificates)
- **No Hard-coded Values**: All configurations are generated from these sources

### **2. Nix-Based Configuration Generation**
- **Manifest Evaluation**: Nix expressions evaluate the manifest to extract configuration values
- **Module Parameterization**: NixOS modules accept manifest parameters instead of hard-coded values
- **Type Safety**: Nix ensures manifest structure is correct and consistent

### **3. Template-Based Approach**
- **NixOS Modules**: Become templates that read from manifest parameters
- **Terraform Configs**: Generated from manifest values using locals and variables
- **Reusable Patterns**: Same module structure works with different manifest values

## **Current Implementation Status**

### **✅ What We've Built:**

1. **Manifest-Driven Caddy Module**
   - Services configuration now reads from manifest instead of hard-coded values
   - Automatic proxy configuration based on manifest `interface.proxy` settings
   - Authentication settings derived from manifest `interface.auth` configuration

2. **Flake Integration**
   - Manifest injected into NixOS module system via `_module.args.manifest`
   - All host configurations receive manifest data through `specialArgs`
   - Modules can access manifest values for dynamic configuration

3. **Orchestrator Manifest Integration**
   - Manifest reading functions: `get_service_ip()`, `get_service_hostname()`, `get_service_dependencies()`
   - No more hard-coded IP addresses or service mappings
   - Dynamic service discovery and configuration

### **🔧 How It Works:**

```nix
# Service Manifest defines the specification
caddy = {
  enable = true;
  ip = "192.168.99.10";
  hostname = "caddy.nixmox.lan";
  interface = {
    proxy = {
      domain = "caddy.nixmox.lan";
      path = "/";
      upstream = "192.168.99.10:80";
      tls = true;
      authz = false;
    };
    health = {
      startup = "systemctl is-active --quiet caddy";
      liveness = "systemctl is-active --quiet caddy";
    };
  };
};

# NixOS Module reads from manifest
{ config, pkgs, lib, manifest, ... }:
let
  serviceConfig = manifest.core_services.caddy or {};
  proxy = serviceConfig.interface.proxy or {};
  domain = proxy.domain or "caddy.${baseDomain}";
in {
  # Configuration generated from manifest values
  services.nixmox.caddy.domain = domain;
  # ... etc
}
```

## **Architecture Benefits**

### **1. Eliminates Configuration Drift**
- **Single source of truth**: Manifest defines everything, no duplicate definitions
- **Consistent values**: IPs, ports, domains all come from one place
- **Easy updates**: Change manifest, rebuild everything automatically

### **2. Self-Contained Services**
- **Service declarations**: Each service defines its own requirements in manifest
- **No host coupling**: Adding a service doesn't require modifying existing hosts
- **Dependency management**: Manifest declares dependencies, orchestrator handles ordering

### **3. Reusable Infrastructure Patterns**
- **Module templates**: Same NixOS modules work with different manifest values
- **Standardized interfaces**: Consistent structure across all services
- **Pattern discovery**: Common configurations become reusable templates

### **4. Type Safety and Validation**
- **Nix evaluation**: Ensures manifest structure is correct before deployment
- **Schema validation**: Manifest format enforces consistent service definitions
- **Compile-time errors**: Catch configuration issues before deployment

## **Implementation Architecture**

### **1. Manifest Structure**
```nix
{
  # Network infrastructure
  network = {
    dns_server = "192.168.99.13";
    gateway = "192.168.99.1";
    domain = "nixmox.lan";
  };

  # Core services (infrastructure)
  core_services = {
    postgresql = { ip = "192.168.99.11"; hostname = "postgresql.nixmox.lan"; ... };
    caddy = { ip = "192.168.99.10"; hostname = "caddy.nixmox.lan"; ... };
    authentik = { ip = "192.168.99.12"; hostname = "authentik.nixmox.lan"; ... };
  };

  # Application services
  services = {
    vaultwarden = {
      ip = "192.168.99.14";
      depends_on = ["postgresql" "caddy" "authentik"];
      interface = {
        proxy = { domain = "vaultwarden.nixmox.lan"; upstream = "192.168.99.14:8080"; };
        auth = { type = "oidc"; provider = "authentik"; };
      };
    };
  };
}
```

### **2. Module Parameterization**
```nix
# Before: Hard-coded values
services = {
  guacamole = {
    domain = "guac.nixmox.lan";  # ❌ Hard-coded
    backend = "guacamole.nixmox.lan";  # ❌ Hard-coded
    port = 8280;  # ❌ Hard-coded
  }
};

# After: Manifest-driven
services = builtins.mapAttrs mkServiceConfig (
  (manifest.core_services or {}) // (manifest.services or {})
);
```

### **3. Orchestrator Manifest Integration**
```bash
# Before: Hard-coded IPs
case "$service" in
    "postgresql") service_ip="192.168.99.11" ;;  # ❌ Hard-coded
    "caddy") service_ip="192.168.99.10" ;;      # ❌ Hard-coded
esac

# After: Manifest-driven
service_ip=$(get_service_ip "$service")  # ✅ Read from manifest
```

## **Deployment Flow**

### **1. Manifest Evaluation**
- Orchestrator reads `service-manifest.nix`
- Extracts service IPs, hostnames, dependencies, and requirements
- Validates manifest structure and completeness

### **2. Configuration Generation**
- **NixOS Configs**: Generated from manifest values injected into module system
- **Terraform Configs**: Generated from manifest values using locals and variables
- **Service Dependencies**: Resolved from manifest dependency declarations

### **3. Deployment Execution**
- **Infrastructure Phase**: Terraform creates/updates LXC containers
- **Configuration Phase**: NixOS deploys generated configurations to hosts
- **Health Verification**: Services checked using manifest-defined health checks

## **Next Steps for Complete Manifest-Driven System**

### **Phase 1: Complete Module Refactoring** ✅
- ✅ Caddy module manifest-driven
- [ ] PostgreSQL module manifest-driven
- [ ] Authentik module manifest-driven
- [ ] Other service modules manifest-driven

### **Phase 2: Terraform Manifest Integration**
- [ ] Generate container specs from manifest
- [ ] Generate network configuration from manifest
- [ ] Generate Authentik resources from manifest

### **Phase 3: SOPS Integration**
- [ ] Merge manifest values with SOPS secrets
- [ ] Inject secrets into generated configurations
- [ ] Secure credential management

### **Phase 4: Advanced Orchestration**
- [ ] Dynamic dependency resolution
- [ ] Incremental deployment based on manifest changes
- [ ] Rollback and recovery mechanisms

## **Long-term Vision**

NixMox will become a **fully declarative infrastructure platform** where:

- **Developers write service manifests** describing what they need
- **Orchestrator handles all complexity** of configuration generation and deployment
- **Infrastructure is reproducible** and maintainable through manifest versioning
- **Services can be added/removed** by updating the manifest
- **No more hard-coded values** anywhere in the system

This transforms NixMox from a collection of manually configured hosts into a **self-orchestrating, manifest-driven infrastructure platform** that truly embodies the "Infrastructure as Code" principle.
