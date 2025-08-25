# Service manifest schema and validation functions
# This provides the foundation for declarative service definitions

{ lib, config, ... }:

let
  # Helper function to create a service definition
  mkService = name: attrs: attrs // {
    _type = "nixmox-service";
    name = name;
  };

  # Service manifest schema
  serviceManifestSchema = {
    # Network configuration
    network = {
      dns_server = lib.mkOption {
        type = lib.types.str;
        description = "DNS server IP address";
        example = "192.168.99.13";
      };
      
      gateway = lib.mkOption {
        type = lib.types.str;
        description = "Default gateway IP address";
        example = "192.168.99.1";
      };
      
      network_cidr = lib.mkOption {
        type = lib.types.str;
        description = "Network CIDR notation";
        example = "192.168.99.0/24";
      };
      
      vlan_tag = lib.mkOption {
        type = lib.types.int;
        description = "VLAN tag for the network";
        example = 99;
      };
    };
    
    # Core services (always required)
    core_services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable this core service";
          };
          
          ip = lib.mkOption {
            type = lib.types.str;
            description = "Static IP address for the service";
            example = "192.168.99.11";
          };
          
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "Hostname for the service";
            example = "postgresql.nixmox.lan";
          };
          
          # Service interface implementation
          interface = lib.mkOption {
            type = lib.types.nullOr (import ./service-interface.nix { inherit lib config; }).serviceInterfaceSchema;
            default = null;
            description = "Service interface implementation";
          };
        };
      });
      default = {};
      description = "Core services that are always required";
    };

    # Service definitions
    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable this service";
          };
          
          ip = lib.mkOption {
            type = lib.types.str;
            description = "Static IP address for the service";
            example = "192.168.99.16";
          };
          
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "Hostname for the service";
            example = "guacamole.nixmox.lan";
          };
          
          depends_on = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "List of service names this service depends on";
            example = ["postgresql", "caddy"];
          };
          
          health_check = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Health check command or URL";
            example = "systemctl is-active guacamole-server";
          };
          
          restart_policy = lib.mkOption {
            type = lib.types.enum ["always" "unless-stopped" "never"];
            default = "unless-stopped";
            description = "Service restart policy";
          };
          
          resources = lib.mkOption {
            type = lib.types.submodule {
              options = {
                memory = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Memory limit";
                  example = "2GB";
                };
                
                cpu = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "CPU limit";
                  example = "2 cores";
                };
                
                storage = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Storage requirement";
                  example = "10GB";
                };
              };
            };
            default = {};
            description = "Resource requirements for the service";
          };
          
          ports = lib.mkOption {
            type = lib.types.listOf lib.types.int;
            default = [];
            description = "Network ports the service uses";
            example = [8280, 4822];
          };
          
          environment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Environment variables for the service";
          };
          
          volumes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Volume mounts for the service";
            example = ["/var/lib/postgresql:/var/lib/postgresql"];
          };
          
          # Service interface implementation
          interface = lib.mkOption {
            type = lib.types.nullOr (import ./service-interface.nix { inherit lib config; }).serviceInterfaceSchema;
            default = null;
            description = "Service interface implementation";
          };
        };
      });
      default = {};
      description = "Service definitions";
    };

    # Deployment phases
    deployment_phases = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        phase1 = ["postgresql", "dns", "caddy"];
        phase2 = ["authentik"];
        phase3 = ["vaultwarden", "guacamole"];
        phase4 = ["monitoring", "nextcloud", "media"];
      };
      description = "Deployment phases and service ordering";
    };

    # Health check definitions
    health_checks = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        postgresql = "systemctl is-active postgresql";
        caddy = "systemctl is-active caddy";
        guacamole = "systemctl is-active tomcat && systemctl is-active guacamole-server";
        authentik = "systemctl is-active authentik";
        vaultwarden = "systemctl is-active vaultwarden";
      };
      description = "Default health check commands for services";
    };
  };

  # Validation functions
  validateServiceManifest = manifest: let
    # Check for circular dependencies
    hasCircularDeps = services: let
      visited = {};
      recStack = {};
      
      hasCycle = serviceName: let
        service = services.${serviceName};
        deps = service.depends_on or [];
      in
        if recStack.${serviceName} or false then
          throw "Circular dependency detected: ${serviceName}"
        else if visited.${serviceName} or false then
          false
        else
          let
            recStack' = recStack // { ${serviceName} = true; };
            visited' = visited // { ${serviceName} = true; };
            result = lib.any hasCycle deps;
            recStack'' = builtins.removeAttrs recStack' [ serviceName ];
          in
            result;
      in
        lib.any hasCycle (builtins.attrNames services);
    
    # Check that all dependencies exist
    validateDependencies = services: let
      serviceNames = builtins.attrNames services;
      allDeps = lib.concatLists (map (name: services.${name}.depends_on or []) serviceNames);
      missingDeps = lib.filter (dep: !(lib.elem dep serviceNames)) allDeps;
    in
      if missingDeps != [] then
        throw "Missing service dependencies: ${lib.concatStringsSep ", " missingDeps}"
      else
        true;
    
    # Check IP address conflicts
    validateIPs = services: let
      ips = lib.mapAttrsToList (name: service: service.ip) services;
      duplicates = lib.filter (ip: lib.count (x: x == ip) ips > 1) ips;
    in
      if duplicates != [] then
        throw "Duplicate IP addresses: ${lib.concatStringsSep ", " (lib.unique duplicates)}"
      else
        true;
    
    # Check hostname conflicts
    validateHostnames = services: let
      hostnames = lib.mapAttrsToList (name: service: service.hostname) services;
      duplicates = lib.filter (hostname: lib.count (x: x == hostname) hostnames > 1) hostnames;
    in
      if duplicates != [] then
        throw "Duplicate hostnames: ${lib.concatStringsSep ", " (lib.unique duplicates)}"
      else
        true;
  in
    if hasCircularDeps manifest.services then
      throw "Service manifest validation failed: circular dependencies"
    else if !(validateDependencies manifest.services) then
      throw "Service manifest validation failed: invalid dependencies"
    else if !(validateIPs manifest.services) then
      throw "Service manifest validation failed: IP conflicts"
    else if !(validateHostnames manifest.services) then
      throw "Service manifest validation failed: hostname conflicts"
    else
      true;

  # Helper function to get service dependencies in order
  getServiceDependencies = services: serviceName: let
    service = services.${serviceName};
    directDeps = service.depends_on or [];
    indirectDeps = lib.concatLists (map (dep: getServiceDependencies services dep) directDeps);
    allDeps = lib.unique (directDeps ++ indirectDeps);
  in
    allDeps;

  # Get deployment order based on dependencies
  getDeploymentOrder = services: let
    # Topological sort using Kahn's algorithm
    inDegree = lib.mapAttrs (name: service: 
      lib.length (service.depends_on or [])
    ) services;
    
    # Find services with no dependencies
    noDeps = lib.filterAttrs (name: degree: degree == 0) inDegree;
    
    # Recursive function to process services
    processServices = remaining: processed: let
      current = lib.attrNames (lib.filterAttrs (name: degree: degree == 0) remaining);
      if current == [] then
        if lib.length (lib.attrNames remaining) > 0 then
          throw "Circular dependency detected in services: ${lib.concatStringsSep ", " (lib.attrNames remaining)}"
        else
          processed
      else
        let
          # Remove processed services and update in-degrees
          remaining' = lib.mapAttrs (name: degree:
            if lib.elem name current then
              -1  # Mark as processed
            else
              degree - (lib.count (dep: lib.elem dep current) (services.${name}.depends_on or []))
          ) remaining;
          
          # Filter out processed services
          remaining'' = lib.filterAttrs (name: degree: degree >= 0) remaining';
        in
          processServices remaining'' (processed ++ current);
    in
      processServices inDegree [];
  in
    getDeploymentOrder;

in {
  # Export the schema and functions
  inherit serviceManifestSchema;
  inherit validateServiceManifest;
  inherit getServiceDependencies;
  inherit getDeploymentOrder;
  inherit mkService;
}