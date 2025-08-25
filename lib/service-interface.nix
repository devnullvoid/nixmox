# Service interface definitions
# All services must implement these interfaces for the orchestrator to deploy them

{ lib, config, ... }:

let
  # Service interface schema
  serviceInterfaceSchema = {
    # Terraform configuration for the service
    terraform = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = "Terraform configuration for this service";
    };
    
    # Authentication configuration
    auth = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = "Authentication configuration";
    };
    
    # Database configuration
    db = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = "Database configuration";
    };
    
    # Reverse proxy configuration
    proxy = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = "Reverse proxy configuration";
    };
    
    # Health check configuration
    health = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = "Health check configuration";
    };
  };

  # Validate service interface
  validateServiceInterface = service: interface: let
    requiredFields = {
      # All services must have basic networking
      networking = ["ip" "hostname"];
      
      # Services with auth must have auth config
      auth = if interface.auth != null then ["auth"] else [];
      
      # Services with proxy must have proxy config
      proxy = if interface.proxy != null then ["proxy"] else [];
      
      # Services with health checks must have health config
      health = if interface.health != null then ["health"] else [];
    };
    
    missingFields = lib.concatLists (lib.mapAttrs (category: fields) requiredFields);
    
    # Check if all required fields are present
    hasRequiredFields = lib.all (field: lib.hasAttr field interface) missingFields;
  in
    if !hasRequiredFields then
      throw "Service ${service.name} missing required interface fields: ${lib.concatStringsSep ", " missingFields}"
    else
      true;

in {
  inherit serviceInterfaceSchema;
  inherit validateServiceInterface;
}