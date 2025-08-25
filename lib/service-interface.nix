# Service interface definitions
# All services must implement these interfaces for the orchestrator to deploy them

{ lib, config, ... }:

let
  # Service interface schema
  serviceInterfaceSchema = {
    # Terraform configuration for the service
    terraform = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          modules = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            description = "Paths to Terraform modules for this service";
            example = ["./terraform/guacamole"];
          };
          
          variables = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
            description = "Variables to pass to Terraform";
            example = {
              domain = "guac.example.com";
              callback_uris = ["https://guac.example.com/oidc/callback"];
            };
          };
          
          targets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Logical targets for reporting/apply order";
            example = ["authentik_app", "authentik_provider", "db_schema"];
          };
          
          apply_order = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Fine-grained sub-apply sequencing";
            example = ["authentik_app", "authentik_provider", "outpost", "db_schema"];
          };
        };
      });
      default = null;
      description = "Terraform configuration for this service";
    };
    
    # Authentication configuration
    auth = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.enum ["oidc" "local" "none"];
            default = "oidc";
            description = "Authentication type";
          };
          
          oidc = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule {
              options = {
                client_id = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "OIDC client ID (auto-generated if null)";
                };
                
                redirect_uris = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "OIDC redirect URIs";
                  example = ["https://guac.example.com/oidc/callback"];
                };
                
                scopes = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = ["openid" "email" "profile"];
                  description = "OIDC scopes to request";
                };
                
                username_claim = lib.mkOption {
                  type = lib.types.str;
                  default = "preferred_username";
                  description = "Claim to use as username";
                };
                
                groups_claim = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = "groups";
                  description = "Claim to use for groups";
                };
              };
            });
            default = null;
            description = "OIDC configuration";
          };
          
          provider = lib.mkOption {
            type = lib.types.str;
            default = "authentik";
            description = "Authentication provider";
          };
        };
      });
      default = null;
      description = "Authentication configuration";
    };
    
    # Database configuration
    db = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          mode = lib.mkOption {
            type = lib.types.enum ["terraform" "native-migration" "none"];
            default = "native-migration";
            description = "Database management mode";
          };
          
          database = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Database name";
          };
          
          role = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Database role name";
          };
          
          migrations = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [];
            description = "Paths to database migration files";
            example = ["./migrations/001-init.sql"];
          };
          
          schema_files = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [];
            description = "Paths to database schema files";
            example = ["./schema/guacamole.sql"];
          };
        };
      });
      default = null;
      description = "Database configuration";
    };
    
    # Reverse proxy configuration
    proxy = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          domain = lib.mkOption {
            type = lib.types.str;
            description = "Domain for the service";
            example = "guac.example.com";
          };
          
          path = lib.mkOption {
            type = lib.types.str;
            default = "/";
            description = "Path prefix for the service";
            example = "/guacamole";
          };
          
          upstream = lib.mkOption {
            type = lib.types.str;
            description = "Upstream service address";
            example = "localhost:8280";
          };
          
          headers = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Additional headers to set";
            example = {
              "X-Forwarded-For" = "{remote_host}";
              "X-Forwarded-Proto" = "{scheme}";
            };
          };
          
          tls = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable TLS";
          };
          
          authz = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Authentik forward auth";
          };
        };
      });
      default = null;
      description = "Reverse proxy configuration";
    };
    
    # Health check configuration
    health = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          startup = lib.mkOption {
            type = lib.types.str;
            description = "Startup health check command or URL";
            example = "systemctl is-active --quiet guacamole-server";
          };
          
          liveness = lib.mkOption {
            type = lib.types.str;
            description = "Liveness health check command or URL";
            example = "curl -f -s http://localhost:8280/guacamole/";
          };
          
          readiness = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Readiness health check command or URL";
            example = "curl -f -s http://localhost:8280/guacamole/api/session/tunnels/active";
          };
          
          timeout = lib.mkOption {
            type = lib.types.int;
            default = 300;
            description = "Health check timeout in seconds";
          };
          
          interval = lib.mkOption {
            type = lib.types.int;
            default = 30;
            description = "Health check interval in seconds";
          };
          
          retries = lib.mkOption {
            type = lib.types.int;
            default = 3;
            description = "Number of health check retries";
          };
        };
      });
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