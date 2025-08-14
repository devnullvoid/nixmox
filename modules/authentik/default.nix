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

    # SOPS secrets for Authentik - shared environment file for all services
    sops.secrets = {
      "authentik/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        # Trigger restarts when secret changes
        restartUnits = [
          "authentik.service"
          "authentik-ldap.service"
          "authentik-radius.service"
          # "authentik-proxy.service"
        ];
      };
      "authentik-ldap/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        path = "/run/secrets/authentik-ldap/env";
        restartUnits = [ "authentik-ldap.service" ];
      };
      "authentik-radius/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        path = "/run/secrets/authentik-radius/env";
        restartUnits = [ "authentik-radius.service" ];
      };
      # (moved) Vaultwarden OIDC secret owned by vaultwarden service in its module
    };

    # Use the official authentik-nix module
    services.authentik = {
      enable = true;
      
      # Use SOPS environment file for secrets
      environmentFile = "/run/secrets/authentik/env";
      
      # Configure settings
      settings = {
        # Email configuration (optional - can be configured later via UI)
        email = {
          host = "smtp.nixmox.lan";
          port = 587;
          username = "authentik@nixmox.lan";
          use_tls = true;
          use_ssl = false;
          from = "authentik@nixmox.lan";
        };
        
        # Disable startup analytics
        disable_startup_analytics = true;
        
        # Use initials for avatars
        avatars = "initials";
        
        # Error reporting
        error_reporting.enabled = false;
        
        # Bootstrap settings to ensure default flows and initial objects exist
        # bootstrap = {
        #   email = cfg.adminEmail;
        # };
        
        # Host configuration for correct redirects/cookies behind proxy
        authentik.host = cfg.domain;
        
        # # Listen configuration
        # listen = {
        #   http = "0.0.0.0:9000";
        #   https = "0.0.0.0:9443";
        # };
        
        # # PostgreSQL configuration
        # postgresql = {
        #   host = "127.0.0.1";
        #   port = 5432;
        #   user = "authentik";
        #   name = "authentik";
        #   password = "authentik123";
        # };
        
        # # Redis configuration - use default port 6379 from authentik-nix module
        # redis = {
        #   host = "127.0.0.1";
        #   port = 6379;
        # };
      };
    };

    # Ensure Authentik knows where to discover blueprints declaratively

    # Add blueprints directory for declarative configuration
    services.authentik.settings.blueprints_dir = blueprintDir;

    # Ship static blueprints declaratively (no runtime copy/rendering services)
    # environment.etc."authentik/blueprints/default-auth-flow.yaml".source = ./blueprints/default-auth-flow.yaml;
    # environment.etc."authentik/blueprints/default-invalidation-flow.yaml".source = ./blueprints/default-invalidation-flow.yaml;
    # Seed providers and outposts (tokens still generated in UI)
    environment.etc."authentik/blueprints/ldap-outpost.yaml".source = ./blueprints/ldap-outpost.yaml;
    environment.etc."authentik/blueprints/radius-outpost.yaml".source = ./blueprints/radius-outpost.yaml;
    # environment.etc."authentik/blueprints/proxy-outpost.yaml".source = ./blueprints/proxy-outpost.yaml;

    # Ensure host resolution for self before DNS exists
    networking.hosts."127.0.0.1" = [ cfg.domain ];

    # Enable outpost services using the same environment file
    # Disable external outposts by default for clean bootstrap; can be enabled later when tokens are set
    services.authentik-ldap = {
      enable = true;
      environmentFile = "/run/secrets/authentik-ldap/env";
    };

    services.authentik-radius = {
      enable = true;
      environmentFile = "/run/secrets/authentik-radius/env";
    };


    # PostgreSQL for Authentik (ensure DB/user and schema ownership)
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "authentik" ];
      ensureUsers = [{
        name = "authentik";
        ensureDBOwnership = true;
      }];
      # Runs on initial cluster/database creation only (no secrets here)
      initialScript = pkgs.writeText "authentik-init.sql" ''
        ALTER SCHEMA public OWNER TO authentik;
      '';
    };

    # Note: Redis is automatically configured by the authentik-nix module
    # on port 6379, so we don't need to configure it manually

    # Set Authentik DB user's password from sops secret at activation time
    systemd.services.postgresql-authentik-password = {
      description = "Set password for PostgreSQL role 'authentik' from sops secret";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "sops-install-secrets.service" ];
      requires = [ "postgresql.service" "sops-install-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        EnvironmentFile = config.sops.secrets."authentik/env".path;
        ExecStart = pkgs.writeShellScript "set-authentik-db-password" ''
          PSQL="${config.services.postgresql.package}/bin/psql"
          # Apply password (idempotent)
          "$PSQL" -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE authentik WITH PASSWORD '$AUTHENTIK_POSTGRESQL__PASSWORD';
SQL
        '';
      };
    };
  };
}