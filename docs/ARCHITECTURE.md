# NixMox Architecture Vision

## **Core Concept: "Docker Compose for Proxmox using NixOS LXCs"**

NixMox aims to be a **container orchestration platform** that uses NixOS LXC containers on Proxmox instead of Docker containers. The goal is to provide the same level of service orchestration and dependency management that Docker Compose offers, but for NixOS-based infrastructure.

## **Architecture Overview**

```
Service Manifests → Orchestrator → Infrastructure Tools
     ↓                    ↓              ↓
"I need DB + Proxy" → Orchestrator → NixOS (hosts) + Terraform (cross-service) + Scripts (deployment)
```

### **Key Components:**

1. **Service Manifests**: Declarative descriptions of what each service needs
2. **Orchestrator**: Intelligent coordinator that reads manifests and provisions infrastructure
3. **Infrastructure Tools**: NixOS for host configuration, Terraform for cross-service resources
4. **Deployment Engine**: Handles ordering, health checks, and incremental updates

## **Current Problem (What We're Solving)**

### **Traditional Approach Issues:**
- **Tight coupling**: Adding a new service requires modifying existing host configurations
- **Monolithic configs**: PostgreSQL host hardcodes all database users, Caddy hardcodes all services
- **Deployment complexity**: Manual ordering of deployments, hard to track dependencies
- **Configuration drift**: Services can't declare their own requirements

### **Example of Current Coupling:**
```nix
# postgresql.nix - hardcodes all services
users.authentik = { ... };
users.guacamole = { ... };
users.vaultwarden = { ... };

# caddy.nix - hardcodes all services  
services.guacamole = { ... };
services.vaultwarden = { ... };
services.nextcloud = { ... };
```

## **Target Architecture (What We're Building)**

### **Service-Centric Design:**
Each service is **self-contained** and declares its own requirements:

```yaml
# services/guacamole/manifest.yaml
name: guacamole
requirements:
  database:
    type: postgresql
    name: guacamole
    user: guacamole
    host: postgresql.nixmox.lan
  
  reverse_proxy:
    type: caddy
    domain: guac.nixmox.lan
    backend: guacamole.nixmox.lan:8280
    auth: true
  
  oidc:
    type: authentik
    provider_name: "Guacamole Provider"
    client_id: guacamole-client
    redirect_uri: https://guac.nixmox.lan/guacamole/
```

### **Orchestrator Responsibilities:**
1. **Read all service manifests**
2. **Generate NixOS configurations** for hosts (databases, users, services)
3. **Manage Terraform resources** for cross-service dependencies (OIDC, reverse proxy)
4. **Handle deployment ordering** based on dependencies
5. **Perform health checks** and incremental updates

### **Benefits:**
- **Self-contained services**: Each service manages its own requirements
- **No host coupling**: Adding a service doesn't require modifying existing hosts
- **Incremental deployment**: Only deploy what changed
- **Declarative**: Manifests describe intent, orchestrator figures out how
- **Reusable patterns**: Same manifest structure for all services

## **Implementation Phases**

### **Phase 1: Prototype (Current)**
- ✅ Get basic services working with manual configuration
- ✅ Establish dependency patterns (PostgreSQL → Caddy → Services)
- ✅ Test deployment workflow with smart deployment script
- 🔄 Get services working end-to-end
- ⏳ Document discovered patterns

### **Phase 2: Manifest System**
- [ ] Define manifest format (YAML/TOML/JSON vs Nix)
- [ ] Create service requirement schemas
- [ ] Build basic orchestrator that reads manifests
- [ ] Convert existing services to use manifests

### **Phase 3: Full Orchestration**
- [ ] Orchestrator generates NixOS configs dynamically
- [ ] Orchestrator manages Terraform resources
- [ ] Full dependency resolution and deployment ordering
- [ ] State management and drift detection

## **Technical Decisions to Make**

### **1. Manifest Format**
- **YAML**: Human-readable, widely supported
- **TOML**: Clean syntax, good for configs
- **JSON**: Universal, programmatic
- **Nix**: Type-safe, integrates with NixOS

### **2. Orchestrator Implementation**
- **Bash script**: Simple, fast, good for prototypes
- **Python**: Rich ecosystem, good for complex logic
- **Nix expression**: Native integration, type safety
- **Go/Rust**: Performance, good for production

### **3. State Management**
- **Git**: Track manifest changes
- **Database**: Track deployment state
- **Terraform state**: Track infrastructure state
- **Hybrid**: Git for manifests, Terraform for infrastructure

## **Current Foundation**

### **Smart Deployment Script**
We've built a foundation with `scripts/deploy-smart.sh` that:
- ✅ Defines service dependencies
- ✅ Deploys in correct order
- ✅ Performs health checks
- ✅ Handles deployment failures gracefully

### **Colmena Integration**
Colmena configuration with `dependsOn` attributes provides:
- ✅ Dependency declaration
- ✅ Deployment ordering
- ✅ Host management

## **Next Steps**

1. **Complete Guacamole prototype** to validate the current approach
2. **Document patterns** discovered during prototype development
3. **Design manifest format** based on real-world requirements
4. **Build orchestrator** that can read manifests and coordinate deployments

## **Long-term Vision**

NixMox will become a **declarative infrastructure platform** where:
- Developers write service manifests
- Orchestrator handles all the complexity
- Infrastructure is reproducible and maintainable
- Services can be added/removed without touching existing hosts

This transforms NixMox from a collection of manually configured hosts into a **self-orchestrating infrastructure platform**.
