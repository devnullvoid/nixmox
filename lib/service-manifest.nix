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
      type = lib.types.attrs;
      default = {};
      description = "Core services that are always required";
    };

    # Service definitions
    services = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Service definitions";
    };
    
    # Deployment phases
    deployment_phases = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Deployment phase definitions";
    };
    
    # Health check configuration
    health_check_timeout = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = "Default health check timeout in seconds";
    };
    
    retry_attempts = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Default number of retry attempts";
    };
    
    retry_delay = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Default delay between retries in seconds";
    };
    
    # Advanced options
    enable_rollback = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable rollback functionality";
    };
    
    enable_health_monitoring = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable health monitoring";
    };
    
    enable_dependency_graphing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable dependency graph generation";
    };
    
    enable_deployment_logging = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable deployment logging";
    };
  };

  # Validate service manifest
  validateServiceManifest = manifest: let
    # Check required fields
    requiredFields = ["network" "core_services" "services"];
    missingFields = lib.filter (field: !(lib.hasAttr field manifest)) requiredFields;
    
    # Check network configuration
    networkValid = if lib.hasAttr "network" manifest then
      let network = manifest.network;
      in lib.all (field: lib.hasAttr field network) ["dns_server" "gateway" "network_cidr" "vlan_tag"]
    else false;
    
    # Check core services
    coreServicesValid = if lib.hasAttr "core_services" manifest then
      lib.all (serviceName: let service = manifest.core_services.${serviceName};
      in lib.all (field: lib.hasAttr field service) ["ip" "hostname"]) (lib.attrNames manifest.core_services)
    else false;
    
    # Check services
    servicesValid = if lib.hasAttr "services" manifest then
      lib.all (serviceName: let service = manifest.services.${serviceName};
      in lib.all (field: lib.hasAttr field service) ["ip" "hostname"]) (lib.attrNames manifest.services)
    else false;
    
    # Validation results
    validationResults = {
      hasRequiredFields = lib.length missingFields == 0;
      networkValid = networkValid;
      coreServicesValid = coreServicesValid;
      servicesValid = servicesValid;
      missingFields = missingFields;
    };
    
    # Check if all validations pass
    isValid = validationResults.hasRequiredFields && 
              validationResults.networkValid && 
              validationResults.coreServicesValid && 
              validationResults.servicesValid;
  in
    if isValid then
      manifest
    else
      throw "Service manifest validation failed: ${lib.generators.toPretty {} validationResults}";

  # Get service dependencies
  getServiceDependencies = services: serviceName: let
    service = services.${serviceName};
  in
    if service != null && lib.hasAttr "depends_on" service then
      service.depends_on
    else
      [];

  # Get deployment order based on dependencies
  getDeploymentOrder = services: let
    # Simple topological sort (for now)
    serviceNames = lib.attrNames services;
    sortedServices = lib.sort (a: b: 
      let depsA = getServiceDependencies services a;
          depsB = getServiceDependencies services b;
      in lib.elem a depsB
    ) serviceNames;
  in
    sortedServices;

in {
  inherit serviceManifestSchema;
  inherit validateServiceManifest;
  inherit getServiceDependencies;
  inherit getDeploymentOrder;
  inherit mkService;
}