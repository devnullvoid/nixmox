{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.authentik;
  blueprintDir = "/etc/authentik/blueprints";
in {
  options.services.nixmox.authentik = {
    enable = mkEnableOption "Authentik identity provider";
    
    subdomain = mkOption {
      type = types.str;
      default = "auth";
      description = "Subdomain for Authentik; full host becomes <subdomain>.<services.nixmox.domain>";
    };

    domain = mkOption {
      type = types.str;
      default = "";
      description = "Domain for Authentik service; if empty, constructed from subdomain + base domain";
    };
    
    adminEmail = mkOption {
      type = types.str;
      default = "admin@nixmox.lan";
      description = "Admin email for Authentik";
    };

    # Database configuration
    database = {
      host = mkOption {
        type = types.str;
        default = "postgresql.nixmox.lan";
        description = "PostgreSQL host";
      };
      
      port = mkOption {
        type = types.int;
        default = 5432;
        description = "PostgreSQL port";
      };
      
      name = mkOption {
        type = types.str;
        default = "authentik";
        description = "PostgreSQL database name";
      };
      
      user = mkOption {
        type = types.str;
        default = "authentik";
        description = "PostgreSQL username";
      };
      
      password = mkOption {
        type = types.str;
        default = "changeme";
        description = "PostgreSQL password (should be overridden via SOPS)";
      };
    };

    # Redis configuration
    redis = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Redis host";
      };
      
      port = mkOption {
        type = types.int;
        default = 6379;
        description = "Redis port";
      };
    };
  };

  config = mkIf cfg.enable {
    # Default domain derived from base domain unless explicitly set by caller
    services.nixmox.authentik.domain = mkDefault "${cfg.subdomain}.${config.services.nixmox.domain}";
    
    # Create authentik user and group early in the activation process
    users.users.authentik = {
      isSystemUser = true;
      group = "authentik";
      description = "Authentik identity provider service user";
    };
    
    users.groups.authentik = {};

    # SOPS secrets for Authentik - temporarily disabled for testing
    # sops.secrets = {
    #   "authentik/env" = {
    #     owner = "authentik";
    #     group = "authentik";
    #     mode = "0400";
    #     # Trigger restarts when secret changes
    #     restartUnits = [
    #       "authentik.service"
    #       "authentik-ldap.service"
    #       "authentik-radius.service"
    #     ];
    #   };
    #   "authentik-ldap/env" = {
    #     owner = "authentik";
    #     group = "authentik";
    #     mode = "0400";
    #     path = "/run/secrets/authentik-ldap/env";
    #     restartUnits = [ "authentik-ldap.service" ];
    #   };
    #   "authentik-radius/env" = {
    #     owner = "authentik";
    #     group = "authentik";
    #     mode = "0400";
    #     path = "/run/secrets/authentik-radius/env";
    #     restartUnits = [ "authentik-radius.service" ];
    #   };
    # };

    # Use the official authentik-nix module - temporarily disabled
    # services.authentik = {
    #   enable = true;
    #   
    #   # Use SOPS environment file for secrets - temporarily disabled
    #   # environmentFile = "/run/secrets/authentik/env";
    #   
    #   # Configure settings
    #   settings = {
    #     # Email configuration (optional - can be configured later via UI)
    #     email = {
    #       host = "smtp.nixmox.lan";
    #       port = 587;
    #       username = "authentik@nixmox.lan";
    #       use_tls = true;
    #       use_ssl = false;
    #       from = "authentik@nixmox.lan";
    #     };
    #     
    #     # Disable startup analytics
    #     disable_startup_analytics = true;
    #     
    #     # Use initials for avatars
    #     avatars = "initials";
    #     
    #     # Error reporting
    #     error_reporting.enabled = false;
    #     
    #     # Bootstrap settings to ensure default flows and initial objects exist
    #     # bootstrap = {
    #     #   email = cfg.adminEmail;
    #     # };
    #     
    #     # Host configuration for correct redirects/cookies behind proxy
    #     authentik.host = cfg.domain;
    #     
    #     # Listen configuration
    #     listen = {
    #       http = "0.0.0.0:9000";
    #       https = "0.0.0.0:9443";
    #     };
    #     
    #     # PostgreSQL configuration - use external database
    #     postgresql = {
    #       host = cfg.database.host;
    #       port = cfg.database.port;
    #       user = cfg.database.user;
    #       name = cfg.database.name;
    #       password = cfg.database.password;
    #     };
    #     
    #     # Redis configuration - use external Redis
    #     redis = {
    #       host = cfg.redis.host;
    #       port = cfg.redis.port;
    #     };
    #   };
    # };

    # Add blueprints directory for declarative configuration - temporarily disabled
    # services.authentik.settings.blueprints_dir = blueprintDir;

    # Ensure host resolution for self before DNS exists
    networking.hosts."127.0.0.1" = [ cfg.domain ];

    # Firewall rules for Authentik services
    networking.firewall = {
      allowedTCPPorts = [ 389 636 9000 9443 ];
      allowedUDPPorts = [ 1812 1813 ];
    };

    # Enable outpost services using the same environment file - temporarily disabled
    # services.authentik-ldap = {
    #   enable = true;
    #   environmentFile = "/run/secrets/authentik-ldap/env";
    # };

    # services.authentik-radius = {
    #   enable = true;
    #   environmentFile = "/run/secrets/authentik-radius/env";
    # };

    # Note: No local PostgreSQL configuration - using external database
    # Note: No local Redis configuration - using external Redis
  };
}