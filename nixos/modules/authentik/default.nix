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
          "AUTHENTIK_HOST=authentik.nixmox.lan"
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
          "AUTHENTIK_HOST=authentik.nixmox.lan"
        ];
        
        # Load secrets from SOPS
        EnvironmentFile = config.sops.secrets."authentik-radius/env".path;
      };
    };



    # Note: Removed hosts entry to allow proper DNS resolution

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