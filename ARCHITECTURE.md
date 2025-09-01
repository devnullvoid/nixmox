# Manifest-Driven Architecture Implementation

## **Overview**

This document provides detailed technical information about how the manifest-driven architecture is implemented in NixMox, including code examples, module patterns, and integration details.

## **Core Implementation Components**

### **1. Service Manifest (`nixos/service-manifest.nix`)**

The service manifest is the single source of truth for all infrastructure configuration. It's written in Nix and defines:

- **Network infrastructure** (IPs, gateways, domains)
- **Core services** (PostgreSQL, Caddy, Authentik, DNS)
- **Application services** (Vaultwarden, Guacamole, Nextcloud, etc.)
- **Service interfaces** (proxy, authentication, health checks)
- **Dependencies** between services

```nix
{
  # Network configuration
  network = {
    dns_server = "192.168.99.13";
    gateway = "192.168.99.1";
    network_cidr = "192.168.99.0/24";
    domain = "nixmox.lan";
    vlan_tag = 99;
  };

  # Core infrastructure services
  core_services = {
    postgresql = {
      enable = true;
      ip = "192.168.99.11";
      hostname = "postgresql.nixmox.lan";
      interface = {
        terraform = {
          modules = [ "./terraform/postgresql" ];
          variables = { domain = "nixmox.lan"; network_cidr = "192.168.99.0/24"; };
        };
        db = {
          name = "postgresql";
          port = 5432;
          mode = "standalone";
        };
        proxy = {
          domain = "postgresql.nixmox.lan";
          path = "/";
          upstream = "192.168.99.11:5432";
          tls = true;
          authz = false;
        };
        health = {
          startup = "systemctl is-active --quiet postgresql";
          liveness = "systemctl is-active --quiet postgresql";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    caddy = {
      enable = true;
      ip = "192.168.99.10";
      hostname = "caddy.nixmox.lan";
      interface = {
        terraform = {
          modules = [ "./terraform/caddy" ];
          variables = { domain = "nixmox.lan"; network_cidr = "192.168.99.0/24"; };
        };
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
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };
  };

  # Application services
  services = {
    vaultwarden = {
      enable = true;
      ip = "192.168.99.14";
      hostname = "vaultwarden.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8080 ];
      interface = {
        terraform = {
          modules = [ "./terraform/vaultwarden" ];
          targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
          variables = {
            domain = "vaultwarden.nixmox.lan";
            oidc_client_id = "vaultwarden-oidc";
            oidc_scopes = [ "openid" "email" "profile" ];
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://vaultwarden.nixmox.lan/oidc/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "vaultwarden.nixmox.lan";
          path = "/";
          upstream = "192.168.99.14:8080";
          tls = true;
          authz = true;
        };
        health = {
          startup = "systemctl is-active --quiet vaultwarden";
          liveness = "curl -f -s http://localhost:8080/alive";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };
  };
}
```

### **2. Flake Integration (`flake.nix`)**

The flake injects the manifest into the NixOS module system, making it available to all modules:

```nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } (top@{ config, withSystem, moduleWithSystem, ... }: {
    imports = [
      ./flake-modules/development.nix
      ./flake-modules/deployment.nix
    ];

    # Import the service manifest and inject it into the module system
    _module.args.manifest = import ./nixos/service-manifest.nix;

    # ... other configuration ...

    flake = {
      # Generate NixOS configurations for each host
      nixosConfigurations = {
        caddy = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nixos/hosts/caddy.nix ];
          specialArgs = { inherit inputs; inherit (config._module.args) manifest; };
        };

        postgresql = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nixos/hosts/postgresql.nix ];
          specialArgs = { inherit inputs; inherit (config._module.args) manifest; };
        };

        # ... other hosts ...
      };
    };
  });
```

### **3. Module Parameterization Pattern**

NixOS modules now accept manifest parameters and use them for configuration:

```nix
# nixos/modules/caddy/default.nix
{ config, pkgs, lib, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = cfg.domain or (network.domain or "nixmox.lan");
  
  # Get Authentik configuration from manifest
  authentikConfig = manifest.core_services.authentik or {};
  authentikDomain = cfg.authentikDomain or (authentikConfig.hostname or "authentik") + "." + baseDomain;
  authentikUpstream = cfg.authentikUpstream or (authentikConfig.ip or "192.168.99.12") + ":9000";
in {
  # ... module configuration using manifest values ...
}
```

### **4. Service Configuration Generation**

The Caddy services module demonstrates how to generate service configurations from the manifest:

```nix
# nixos/modules/caddy/services.nix
{ config, pkgs, lib, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
  baseDomain = cfg.domain;
  
  # Helper function to get service config from manifest
  getServiceConfig = serviceName: 
    manifest.services.${serviceName} or manifest.core_services.${serviceName} or {};
  
  # Helper function to build service proxy configuration
  mkServiceConfig = serviceName: serviceConfig:
    let
      # Get proxy configuration from manifest
      proxy = serviceConfig.interface.proxy or {};
      # Get authentication configuration from manifest
      auth = serviceConfig.interface.auth or {};
      
      # Determine if auth is enabled based on manifest
      enableAuth = auth.type == "oidc" && auth.provider == "authentik";
      
      # Get backend from manifest (prefer proxy.upstream, fallback to hostname:port)
      backend = proxy.upstream or "${serviceConfig.hostname}:${toString (proxy.port or 80)}";
      
      # Get domain from manifest
      domain = proxy.domain or "${serviceName}.${baseDomain}";
      
      # Get port from manifest
      port = proxy.port or 80;
      
      # Generate extra config based on service type and auth requirements
      extraConfig = if serviceName == "guacamole" then ''
        # Guacamole reverse proxy configuration
        reverse_proxy ${backend}
      '' else if enableAuth then ''
        # Service with Authentik OIDC authentication
        header {
          X-Content-Type-Options nosniff
          X-Frame-Options SAMEORIGIN
          X-XSS-Protection "1; mode=block"
          Referrer-Policy strict-origin-when-cross-origin
          -Server
        }
        
        # Authentik forward auth
        forward_auth authentik.nixmox.lan:9000 {
          except /health /metrics /alive
        }
      '' else ''
        # Service without authentication
        header {
          X-Content-Type-Options nosniff
          X-Frame-Options SAMEORIGIN
          X-XSS-Protection "1; mode=block"
          Referrer-Policy strict-origin-when-cross-origin
          -Server
        }
      '';
    in {
      domain = domain;
      backend = backend;
      port = port;
      enableAuth = enableAuth;
      skipDefaultProxy = serviceName == "guacamole" || (proxy.path or "/") != "/";
      extraConfig = extraConfig;
    };
  
  # Generate services configuration from manifest
  servicesConfig = builtins.mapAttrs mkServiceConfig (
    # Combine core services and application services
    (manifest.core_services or {}) // (manifest.services or {})
  );
in {
  config = mkIf cfg.enable {
    # Configure all services to be proxied through Caddy
    # Services are now generated from the manifest instead of hard-coded
    services.nixmox.caddy.services = servicesConfig;
  };
}
```

### **5. Orchestrator Manifest Integration**

The orchestrator script now reads values from the manifest instead of using hard-coded values:

```bash
# scripts/deploy-orchestrator.sh

# Manifest reading functions
get_service_ip() {
    local service="$1"
    
    # Try to get IP from core_services first, then from services
    local ip=$(nix eval -f "$MANIFEST_PATH" "core_services.$service.ip" --raw 2>/dev/null || \
                nix eval -f "$MANIFEST_PATH" "services.$service.ip" --raw 2>/dev/null)
    
    if [[ -z "$ip" ]]; then
        log_error "Could not find IP address for service: $service"
        return 1
    fi
    
    echo "$ip"
}

get_service_hostname() {
    local service="$1"
    
    # Try to get hostname from core_services first, then from services
    local hostname=$(nix eval -f "$MANIFEST_PATH" "core_services.$service.hostname" --raw 2>/dev/null || \
                     nix eval -f "$MANIFEST_PATH" "services.$service.hostname" --raw 2>/dev/null)
    
    if [[ -z "$hostname" ]]; then
        log_error "Could not find hostname for service: $service"
        return 1
    fi
    
    echo "$hostname"
}

get_service_dependencies() {
    local service="$1"
    
    # Try to get dependencies from services (core_services don't have dependencies)
    local deps=$(nix eval -f "$MANIFEST_PATH" "services.$service.depends_on" --json 2>/dev/null || echo "[]")
    
    echo "$deps"
}

# Usage in deployment functions
deploy_service() {
    local service="$1"
    
    log_info "Deploying $service using NixOS..."
    
    # Get the IP address for the service from manifest
    local service_ip
    if ! service_ip=$(get_service_ip "$service"); then
        log_error "Failed to get IP address for $service"
        return 1
    fi
    
    # ... rest of deployment logic using manifest-driven values ...
}
```

## **Integration Patterns**

### **1. Host Configuration Pattern**

Host configurations now receive manifest data and can use it for dynamic configuration:

```nix
# nixos/hosts/caddy.nix
{ config, lib, pkgs, inputs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
  
  # Get Caddy service configuration from manifest
  caddyConfig = manifest.core_services.caddy or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
in {
  imports = [
    ../modules/core.nix
    ../modules/caddy
    ../modules/shared/internal-ca.nix
  ];

  # Host-specific configuration
  networking.hostName = caddyConfig.hostname or "caddy";
  
  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Enable Caddy service with manifest-driven configuration
  services.nixmox.caddy = {
    enable = true;
    developmentMode = false;
    useInternalCa = true;
    caCertPath = ../ca/nixmox-internal-ca.crt;
    caName = "NixMox Internal CA";
    domain = baseDomain;
  };
  
  # Enable internal CA with wildcard private key
  services.nixmox.internalCa = {
    enable = true;
    caCertPath = ../ca/nixmox-internal-ca.crt;
    wildcardCertPath = ../ca/wildcard-nixmox-lan.crt;
    enableWildcardKey = true;
  };



  # Firewall rules for Caddy
  networking.firewall = {
    allowedTCPPorts = [
      80   # HTTP
      443  # HTTPS
      9090 # Caddy metrics
    ];
  };
}
```

### **2. Service Module Pattern**

Service modules become templates that can work with any manifest values:

```nix
# nixos/modules/postgresql/default.nix
{ config, pkgs, lib, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.postgresql;
  
  # Get all services that need databases from manifest
  allServices = (manifest.core_services or {}) // (manifest.services or {});
  
  # Extract database requirements from services
  databaseRequirements = builtins.mapAttrs (serviceName: serviceConfig:
    serviceConfig.interface.db or {}
  ) (builtins.filterAttrs (name: config: 
    builtins.hasAttr "db" (config.interface or {})
  ) allServices);
  
  # Generate database configurations
  databases = builtins.mapAttrs (serviceName: dbConfig:
    {
      name = dbConfig.name or serviceName;
      owner = dbConfig.owner or serviceName;
      extensions = dbConfig.extensions or [];
    }
  ) databaseRequirements;
  
  # Generate user configurations
  users = builtins.mapAttrs (serviceName: dbConfig:
    {
      name = dbConfig.owner or serviceName;
      password = dbConfig.password or "changeme"; # TODO: Use SOPS
      databases = [ (dbConfig.name or serviceName) ];
      superuser = dbConfig.superuser or false;
    }
  ) databaseRequirements;
in {
  options.services.nixmox.postgresql = {
    enable = mkEnableOption "PostgreSQL database service";
    
    # Allow manual override of manifest values
    databases = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          owner = mkOption { type = types.str; };
          extensions = mkOption { type = types.listOf types.str; default = []; };
        };
      });
      default = databases;
      description = "Databases to create (auto-generated from manifest)";
    };
    
    users = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          password = mkOption { type = types.str; };
          databases = mkOption { type = types.listOf types.str; };
          superuser = mkOption { type = types.bool; default = false; };
        };
      });
      default = users;
      description = "Database users to create (auto-generated from manifest)";
    };
  };

  config = mkIf cfg.enable {
    # PostgreSQL service configuration
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_15;
      
      # Create databases from manifest
      ensureDatabases = builtins.attrValues (builtins.mapAttrs (name: db: db.name) cfg.databases);
      
      # Create users from manifest
      ensureUsers = builtins.attrValues (builtins.mapAttrs (name: user: {
        name = user.name;
        ensurePermissions = builtins.mapAttrs (dbName: db: 
          "DATABASE ${db.name}" = "ALL PRIVILEGES"
        ) cfg.databases;
      }) cfg.users);
    };
    
    # ... rest of PostgreSQL configuration ...
  };
}
```

## **Benefits of This Architecture**

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

## **Next Steps**

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

This manifest-driven architecture transforms NixMox from a collection of manually configured hosts into a **self-orchestrating, manifest-driven infrastructure platform** that truly embodies the "Infrastructure as Code" principle.
