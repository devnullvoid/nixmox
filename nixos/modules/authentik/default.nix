{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.authentik;
  
  # Get Authentik service configuration from manifest
  authentikConfig = manifest.core_services.authentik or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get database configuration from manifest or use defaults
  dbConfig = authentikConfig.interface.db or {};
  databaseHost = dbConfig.host or "postgresql.nixmox.lan";
  databasePort = dbConfig.port or 5432;
  databaseName = dbConfig.name or "authentik";
  databaseUser = dbConfig.owner or "authentik";
  
  # Get domain from manifest or construct from subdomain
  serviceDomain = cfg.domain or (authentikConfig.interface.proxy.domain or "auth.${baseDomain}");
  
  # Get admin email from manifest or use default
  adminEmail = authentikConfig.admin_email or "admin@${baseDomain}";
  
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
      description = "Domain for Authentik service; if empty, constructed from manifest or subdomain + base domain";
    };
    
    adminEmail = mkOption {
      type = types.str;
      default = "";
      description = "Admin email for Authentik; if empty, uses manifest value or default";
    };

    # Database configuration
    database = {
      host = mkOption {
        type = types.str;
        default = "";
        description = "PostgreSQL host; if empty, uses manifest value or default";
      };
      
      port = mkOption {
        type = types.int;
        default = 0;
        description = "PostgreSQL port; if 0, uses manifest value or default";
      };
      
      name = mkOption {
        type = types.str;
        default = "";
        description = "PostgreSQL database name; if empty, uses manifest value or default";
      };
      
      user = mkOption {
        type = types.str;
        default = "";
        description = "PostgreSQL username; if empty, uses manifest value or default";
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
    # Use manifest values with fallbacks to manual configuration
    services.nixmox.authentik.domain = mkDefault serviceDomain;
    services.nixmox.authentik.adminEmail = mkDefault adminEmail;
    
    # Database configuration with manifest fallbacks
    services.nixmox.authentik.database = {
      host = mkDefault databaseHost;
      port = mkDefault databasePort;
      name = mkDefault databaseName;
      user = mkDefault databaseUser;
    };
    
    # Create authentik user and group early in the activation process
    users.users.authentik = {
      isSystemUser = true;
      group = "authentik";
      description = "Authentik identity provider service user";
    };
    
    users.groups.authentik = {};

    # Enable local Redis for Authentik
    services.redis.servers."".enable = true;
    services.redis.servers."".settings = {
      bind = "127.0.0.1";
      port = cfg.redis.port;
      # Basic security settings
      protected-mode = "yes";
      # Performance settings
      maxmemory = "256mb";
      maxmemory-policy = "allkeys-lru";
    };

    # SOPS secrets for Authentik
    sops.secrets = {
      "authentik/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        # Trigger restarts when secret changes
        restartUnits = [
          "authentik.service"
          "authentik-worker.service"
        ];
      };
      "authentik-ldap/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [ "authentik-ldap.service" ];
      };
      "authentik-radius/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [ "authentik-radius.service" ];
      };
    };

    # Use the official Nixpkgs Authentik packages
    environment.systemPackages = with pkgs; [
      authentik
      authentik-outposts.ldap
      authentik-outposts.proxy
      authentik-outposts.radius
    ];

    # Create Authentik systemd service
    systemd.services.authentik = {
      description = "Authentik Identity Provider";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "redis.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/tmp"; # Use /tmp temporarily to avoid directory issues
        ExecStart = "${pkgs.authentik}/bin/ak server";
        Restart = "always";
        RestartSec = "10s";
        
        # Environment variables for configuration
        Environment = [
          "AUTHENTIK_LISTEN__HTTP=0.0.0.0:9000"
          "AUTHENTIK_LISTEN__HTTPS=0.0.0.0:9443"
          "AUTHENTIK_POSTGRESQL__HOST=${cfg.database.host}"
          "AUTHENTIK_POSTGRESQL__PORT=${toString cfg.database.port}"
          "AUTHENTIK_POSTGRESQL__USER=${cfg.database.user}"
          "AUTHENTIK_POSTGRESQL__NAME=${cfg.database.name}"
          "AUTHENTIK_REDIS__HOST=${cfg.redis.host}"
          "AUTHENTIK_REDIS__PORT=${toString cfg.redis.port}"
          "AUTHENTIK_AUTHENTIK__HOST=${cfg.domain}"
          "AUTHENTIK_AUTHENTIK__INSECURE=true"
          "AUTHENTIK_AUTHENTIK__DISABLE_UPDATE_CHECK=true"
          "AUTHENTIK_AUTHENTIK__CREATE_DEFAULT_FLOWS=true"  
          "AUTHENTIK_BLUEPRINTS__AUTO_IMPORT=true"
          "AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true"
          "AUTHENTIK_ERROR_REPORTING__ENABLED=false"
          "AUTHENTIK_AVATARS=initials"
        ];
        
        # Load secrets from SOPS
        EnvironmentFile = config.sops.secrets."authentik/env".path;
      };
    };

    # Create Authentik Celery worker service
    systemd.services.authentik-worker = {
      description = "Authentik Celery Worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "redis.service" "authentik.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/tmp"; # Use /tmp temporarily to avoid directory issues
        ExecStart = "${pkgs.authentik}/bin/ak worker";
        Restart = "always";
        RestartSec = "10s";
        
        # Environment variables for configuration (same as main service)
        Environment = [
          "AUTHENTIK_POSTGRESQL__HOST=${cfg.database.host}"
          "AUTHENTIK_POSTGRESQL__PORT=${toString cfg.database.port}"
          "AUTHENTIK_POSTGRESQL__USER=${cfg.database.user}"
          "AUTHENTIK_POSTGRESQL__NAME=${cfg.database.name}"
          "AUTHENTIK_REDIS__HOST=${cfg.redis.host}"
          "AUTHENTIK_REDIS__PORT=${toString cfg.redis.port}"
          "AUTHENTIK_AUTHENTIK__HOST=${cfg.domain}"
          "AUTHENTIK_AUTHENTIK__INSECURE=true"
          "AUTHENTIK_AUTHENTIK__DISABLE_UPDATE_CHECK=true"
          "AUTHENTIK_AUTHENTIK__CREATE_DEFAULT_FLOWS=true"  
          "AUTHENTIK_BLUEPRINTS__AUTO_IMPORT=true"
          "AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true"
          "AUTHENTIK_ERROR_REPORTING__ENABLED=false"
          "AUTHENTIK_AVATARS=initials"
        ];
        
        # Load secrets from SOPS
        EnvironmentFile = config.sops.secrets."authentik/env".path;
      };
    };

    # Create Authentik LDAP outpost service
    systemd.services.authentik-ldap = {
      description = "Authentik LDAP Outpost";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "authentik.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/tmp"; # Use /tmp temporarily to avoid directory issues
        ExecStart = "${pkgs.authentik-outposts.ldap}/bin/ldap";
        Restart = "always";
        RestartSec = "10s";
        
        # Environment variables for LDAP outpost
        Environment = [
          "AUTHENTIK_HOST=${cfg.domain}"
        ];
        
        # Load secrets from SOPS
        EnvironmentFile = config.sops.secrets."authentik-ldap/env".path;
      };
    };

    # Create Authentik Radius outpost service
    systemd.services.authentik-radius = {
      description = "Authentik Radius Outpost";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "authentik.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/tmp"; # Use /tmp temporarily to avoid directory issues
        ExecStart = "${pkgs.authentik-outposts.radius}/bin/radius";
        Restart = "always";
        RestartSec = "10s";
        
        # Environment variables for Radius outpost
        Environment = [
          "AUTHENTIK_HOST=${cfg.domain}"
        ];
        
        # Load secrets from SOPS
        EnvironmentFile = config.sops.secrets."authentik-radius/env".path;
      };
    };

    # Firewall rules for Authentik services
    networking.firewall = {
      allowedTCPPorts = [ 389 636 9000 9443 ];
      allowedUDPPorts = [ 1812 1813 ];
    };
  };
}