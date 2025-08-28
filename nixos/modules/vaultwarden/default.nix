{ config, lib, pkgs, manifest, ... }:

with lib;

# Vaultwarden PostgreSQL Configuration (Manifest-Driven)
#
# This module configures Vaultwarden to use PostgreSQL instead of SQLite.
# All configuration values are now driven by the service manifest.
#
# Database configuration is automatically constructed from manifest values:
# - Host: from manifest.services.vaultwarden.interface.db.host
# - Port: from manifest.services.vaultwarden.interface.db.port
# - Database: from manifest.services.vaultwarden.interface.db.name
# - User: from manifest.services.vaultwarden.interface.db.owner
# - Password: from SOPS secrets

let
  cfg = config.services.nixmox.vaultwarden;

  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";

  # Get service configuration from manifest
  serviceConfig = manifest.services.vaultwarden or {};

  # Get database configuration from manifest
  dbConfig = serviceConfig.interface.db or {};

  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};

  # Get authentication configuration from manifest
  authConfig = serviceConfig.interface.auth or {};

  # Construct database URL from manifest values
  databaseUrl = "postgresql://${dbConfig.owner or "vaultwarden"}:***@${dbConfig.host or "postgresql.nixmox.lan"}:${toString (dbConfig.port or 5432)}/${dbConfig.name or "vaultwarden"}";
in {
  options.services.nixmox.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager";
    
    domain = mkOption {
      type = types.str;
      default = proxyConfig.domain or "vaultwarden.nixmox.lan";
      description = "Domain for Vaultwarden service (from manifest proxy config)";
    };

    primaryDomain = mkOption {
      type = types.str;
      default = baseDomain;
      description = "Primary domain for services (from manifest network config)";
    };
    
    # Vaultwarden configuration
    vaultwarden = {
      port = mkOption {
        type = types.int;
        default = 8080;
        description = "Vaultwarden web interface port";
      };
      
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/vaultwarden";
        description = "Vaultwarden data directory";
      };
      
      # Database configuration (manifest-driven)
      database = {
        url = mkOption {
          type = types.str;
          default = databaseUrl;
          description = "Database URL for Vaultwarden (constructed from manifest)";
        };

        host = mkOption {
          type = types.str;
          default = dbConfig.host or "postgresql.nixmox.lan";
          description = "PostgreSQL host address (from manifest)";
        };

        port = mkOption {
          type = types.int;
          default = dbConfig.port or 5432;
          description = "PostgreSQL port (from manifest)";
        };

        name = mkOption {
          type = types.str;
          default = dbConfig.name or "vaultwarden";
          description = "PostgreSQL database name (from manifest)";
        };

        user = mkOption {
          type = types.str;
          default = dbConfig.owner or "vaultwarden";
          description = "PostgreSQL username (from manifest)";
        };
      };
      
      # Web vault configuration
      webVault = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable web vault interface";
        };
        
        path = mkOption {
          type = types.str;
          default = "/var/lib/vaultwarden/web-vault";
          description = "Web vault files path";
        };
      };
      
      # Environment variables
      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Environment variables for Vaultwarden";
      };
      
      # Admin token
      adminToken = mkOption {
        type = types.str;
        default = "changeme";
        description = "Admin token for Vaultwarden (should be overridden via SOPS)";
      };
      
      # Domain settings
      domain = mkOption {
        type = types.str;
        default = "https://vault.nixmox.lan";
        description = "Domain for Vaultwarden";
      };
      
      # Security settings
      security = {
        # JWT secret
        jwtSecret = mkOption {
          type = types.str;
          default = "changeme";
          description = "JWT secret for Vaultwarden (should be overridden via SOPS)";
        };
        
        # Signups allowed
        signupsAllowed = mkOption {
          type = types.bool;
          default = false;
          description = "Allow new user signups";
        };
        
        # Invitations allowed
        invitationsAllowed = mkOption {
          type = types.bool;
          default = true;
          description = "Allow invitations";
        };
      };
      
      # Email settings
      email = {
        smtpHost = mkOption {
          type = types.str;
          default = "mail.nixmox.lan";
          description = "SMTP host for email";
        };
        
        smtpPort = mkOption {
          type = types.int;
          default = 587;
          description = "SMTP port for email";
        };
        
        smtpFrom = mkOption {
          type = types.str;
          default = "vaultwarden@nixmox.lan";
          description = "SMTP from address";
        };
        
        smtpUsername = mkOption {
          type = types.str;
          default = "vaultwarden";
          description = "SMTP username";
        };
        
        smtpPassword = mkOption {
          type = types.str;
          default = "changeme";
          description = "SMTP password (should be overridden via SOPS)";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # SOPS secrets for Vaultwarden
    sops.secrets = {
      "vaultwarden/env" = {
        owner = "vaultwarden";
        group = "vaultwarden";
        mode = "0400";
        path = "/run/secrets/vaultwarden/env";
        restartUnits = [ "vaultwarden.service" ];
      };
      
      "vaultwarden/database_password" = {
        owner = "vaultwarden";
        group = "vaultwarden";
        mode = "0400";
        restartUnits = [ "vaultwarden.service" ];
      };
    };

    # Optionally, include OIDC values directly in vaultwarden/env for POC

    # Vaultwarden service
    services.vaultwarden = {
      enable = true;
      
      # Basic settings
      config = {
        # Domain
        DOMAIN = cfg.vaultwarden.domain;
        
        # Database (PostgreSQL connection - password set via SOPS EnvironmentFile)
        DATABASE_URL = "postgresql://${cfg.vaultwarden.database.user}:***@${cfg.vaultwarden.database.host}:${toString cfg.vaultwarden.database.port}/${cfg.vaultwarden.database.name}";
        
        # Admin token and JWT secret are expected via SOPS EnvironmentFile
        SIGNUPS_ALLOWED = cfg.vaultwarden.security.signupsAllowed;
        INVITATIONS_ALLOWED = cfg.vaultwarden.security.invitationsAllowed;
        
        # Email settings
        SMTP_HOST = cfg.vaultwarden.email.smtpHost;
        SMTP_PORT = toString cfg.vaultwarden.email.smtpPort;
        SMTP_FROM = cfg.vaultwarden.email.smtpFrom;
        SMTP_USERNAME = cfg.vaultwarden.email.smtpUsername;
        SMTP_PASSWORD = cfg.vaultwarden.email.smtpPassword;
        SMTP_SECURITY = "starttls";
        
        # Web vault (enable embedded web vault so "/" serves UI)
        WEB_VAULT_ENABLED = true;
        
        # Additional environment variables
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = toString cfg.vaultwarden.port;
        ROCKET_WORKERS = "10";
        
        # Logging
        LOG_LEVEL = "warn";
        
        # Performance
        ENABLE_DB_WAL = "true";
        ENABLE_EXTENDED_LOGGING = "true";
        
        # Security headers
        SECURITY_HEADERS = "true";
        
        # Additional custom environment variables
      } // cfg.vaultwarden.environment // {
        # OIDC with Authentik (configure via sops env for secrets)
        OIDC_ENABLED = "true";
        OIDC_DISPLAY_NAME = "Authentik";
        OIDC_USER_CLAIM = "email";
        OIDC_SCOPE = "openid email profile";
        # The following should be set through the EnvironmentFile (sops):
        # OIDC_ISSUER=https://auth.nixmox.lan/application/o/<provider_slug>/
        # OIDC_CLIENT_ID=...
        # OIDC_CLIENT_SECRET=...
        # OIDC_REDIRECT_URI=https://vault.nixmox.lan/oidc/callback

        # SSO button support in web-vault (non-sensitive here; secrets in sops env)
        # Ref: https://github.com/Timshel/vaultwarden/blob/sso-support/SSO.md
        SSO_ENABLED = "true";
        SSO_ONLY = "false";
        SSO_DISPLAY_NAME = "Authentik";
        # Match provider scopes and docs: include offline_access
        SSO_SCOPES = "email profile offline_access";
        # Provide these via sops env file (vaultwarden/env):
        # SSO_AUTHORITY=https://auth.nixmox.lan/application/o/vaultwarden-oidc/
        # SSO_CLIENT_ID=...
        # SSO_CLIENT_SECRET=...
      };
    };
    
    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        cfg.vaultwarden.port  # Vaultwarden (reverse-proxied by Caddy)
      ];
    };
    
    # Create Vaultwarden user
    users.users.vaultwarden = {
      isSystemUser = true;
      group = "vaultwarden";
      home = cfg.vaultwarden.dataDir;
      createHome = true;
    };
    
    users.groups.vaultwarden = {};
    
    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.vaultwarden.dataDir} 0755 vaultwarden vaultwarden"
      "d ${cfg.vaultwarden.dataDir}/data 0755 vaultwarden vaultwarden"
      "d ${cfg.vaultwarden.webVault.path} 0755 vaultwarden vaultwarden"
      # logging to journal; no on-disk log file needed
    ];
    
    # Systemd services
    systemd.services = {
      # Vaultwarden service
      "vaultwarden" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        
        serviceConfig = {
          ExecStartPre = [
            # Ensure all required directories exist before starting
            "${pkgs.coreutils}/bin/mkdir -p ${cfg.vaultwarden.dataDir}"
            "${pkgs.coreutils}/bin/mkdir -p ${cfg.vaultwarden.dataDir}/data"
            "${pkgs.coreutils}/bin/mkdir -p ${cfg.vaultwarden.webVault.path}"
            # Set proper ownership
            "${pkgs.coreutils}/bin/chown -R vaultwarden:vaultwarden ${cfg.vaultwarden.dataDir}"
            "${pkgs.coreutils}/bin/chown -R vaultwarden:vaultwarden ${cfg.vaultwarden.webVault.path}"
          ];
          # User and group
          User = "vaultwarden";
          Group = "vaultwarden";
          
          # Working directory
          WorkingDirectory = cfg.vaultwarden.dataDir;
          
          # Sensitive environment via SOPS
          EnvironmentFile = config.sops.secrets."vaultwarden/env".path;

          # Environment
          Environment = lib.mapAttrsToList (name: value: "${name}=${toString value}") (config.services.vaultwarden.config);
          
          # Security settings
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          
          # Capabilities
          AmbientCapabilities = "CAP_NET_BIND_SERVICE";
          CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
          
          # Logging
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
      # Nginx is not used; Caddy handles reverse proxying
    };
    
    # Health check for Vaultwarden
    systemd.services.vaultwarden-health = {
      description = "Vaultwarden health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "vaultwarden.service" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in {1..20}; do ${pkgs.curl}/bin/curl -fs http://localhost:${toString cfg.vaultwarden.port}/alive && exit 0; sleep 2; done; exit 1'";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };
    
    # Default environment variables
    services.nixmox.vaultwarden.vaultwarden.environment = {
      # Additional security settings
      DISABLE_ICON_DOWNLOAD = "false";
      ICON_CACHE_TTL = "2592000";
      ICON_CACHE_NEGTTL = "259200";
      
      # Database settings (PostgreSQL)
      DATABASE_MAX_CONNS = "10";
      DATABASE_URL = "postgresql://vaultwarden:***@192.168.99.11:5432/vaultwarden";
      
      # PostgreSQL-specific settings
      DATABASE_TIMEOUT = "30";
      DATABASE_CONNECTION_RETRIES = "3";
      DATABASE_POOL_SIZE = "10";
      
      # Email settings
      SMTP_TIMEOUT = "15";
      SMTP_ACCEPT_INVALID_HOSTNAMES = "false";
      SMTP_ACCEPT_INVALID_CERTS = "false";
      
      # Security settings
      SHOW_PASSWORD_HINT = "false";
      PASSWORD_HINTS_ALLOWED = "false";
      DISABLE_2FA_REMEMBER = "false";
      
      # Organization settings
      ORG_CREATION_USERS = "admin@${cfg.primaryDomain}";
      
      # Backup settings
      BACKUP_FREQUENCY = "12h";
      BACKUP_ATTEMPTS = "3";
      
      # Logging (to journal)
      EXTENDED_LOGGING = "true";
    };
  };
} 