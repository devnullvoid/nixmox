{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.nextcloud;

  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";

  # Get service configuration from manifest
  serviceConfig = manifest.services.nextcloud or {};

  # Get database configuration from manifest
  dbConfig = serviceConfig.interface.db or {};

  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};

  # Get authentication configuration from manifest
  authConfig = serviceConfig.interface.auth or {};

  # Get core services for dependencies
  coreServices = manifest.core_services or {};

  # Generate configuration from manifest
  manifestConfig = {
    # Use proxy.domain from manifest
    hostName = proxyConfig.domain or "nextcloud.${baseDomain}";
    
    # Use authentik domain from manifest
    authentikDomain = (coreServices.authentik.interface.proxy.domain or "auth.${baseDomain}");
    
    # Use OIDC provider path from manifest (default to service name)
    oidcProviderPath = "nextcloud";
    
    # Use client ID from manifest
    clientId = authConfig.oidc.client_id or "nextcloud-oidc";
    
    # Use OIDC configuration from manifest
    auth = {
      oidc = {
        scopes = authConfig.oidc.scopes or [ "openid" "email" "profile" ];
        username_claim = authConfig.oidc.username_claim or "preferred_username";
        groups_claim = authConfig.oidc.groups_claim or "groups";
      };
    };
    
    # Use database configuration from manifest
    database = {
      host = dbConfig.host or coreServices.postgresql.ip or "postgresql.${baseDomain}";
      port = dbConfig.port or 5432;
      name = dbConfig.name or "nextcloud";
      user = dbConfig.owner or "nextcloud";
      # Password will come from SOPS database_password secret
    };
  };

in {
  options.services.nixmox.nextcloud = {
    enable = mkEnableOption "Nextcloud file sharing platform";

    # Allow manual overrides of manifest values
    hostName = mkOption {
      type = types.str;
      default = manifestConfig.hostName;
      description = "Public host name for Nextcloud (from manifest proxy config)";
    };

    # Database configuration (manifest-driven with overrides)
    database = {
      type = mkOption {
        type = types.enum [ "postgresql" "mysql" "sqlite" ];
        default = "postgresql";
        description = "Database type to use";
      };

      host = mkOption {
        type = types.str;
        default = manifestConfig.database.host;
        description = "Database host (from manifest)";
      };

      port = mkOption {
        type = types.int;
        default = manifestConfig.database.port;
        description = "Database port (from manifest)";
      };

      name = mkOption {
        type = types.str;
        default = manifestConfig.database.name;
        description = "Database name (from manifest)";
      };

      user = mkOption {
        type = types.str;
        default = manifestConfig.database.user;
        description = "Database user (from manifest)";
      };
    };

    # Redis configuration
    redis = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Redis caching";
      };

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

    # Nextcloud configuration
    nextcloud = {
      port = mkOption {
        type = types.int;
        default = 8080;
        description = "Nextcloud web interface port (behind Caddy)";
      };

      storage = {
        dataDir = mkOption {
          type = types.str;
          default = "/var/lib/nextcloud/data";
          description = "Nextcloud data storage directory";
        };
      };

      # Admin configuration
      adminUser = mkOption {
        type = types.str;
        default = "admin";
        description = "Nextcloud admin username";
      };
    };

    # OIDC configuration (manifest-driven)
    oidc = {
      clientId = mkOption {
        type = types.str;
        default = manifestConfig.clientId;
        description = "OIDC client ID (from manifest)";
      };

      authentikDomain = mkOption {
        type = types.str;
        default = manifestConfig.authentikDomain;
        description = "Authentik domain (from manifest)";
      };

      providerPath = mkOption {
        type = types.str;
        default = manifestConfig.oidcProviderPath;
        description = "OIDC provider path (from manifest)";
      };

      scopes = mkOption {
        type = types.listOf types.str;
        default = manifestConfig.auth.oidc.scopes or [ "openid" "email" "profile" ];
        description = "OIDC scopes (from manifest)";
      };

      usernameClaim = mkOption {
        type = types.str;
        default = manifestConfig.auth.oidc.username_claim or "preferred_username";
        description = "OIDC username claim (from manifest)";
      };

      groupsClaim = mkOption {
        type = types.str;
        default = manifestConfig.auth.oidc.groups_claim or "groups";
        description = "OIDC groups claim (from manifest)";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    let
      hostNameEffective = cfg.hostName;
    in {
      # SOPS secrets for Nextcloud
      sops.secrets.nextcloud_admin_password = {
        sopsFile = ../../../secrets/default.yaml;
        key = "nextcloud/admin_password";
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
        restartUnits = [ "nextcloud-setup.service" ];
      };

      sops.secrets.nextcloud_database_password = {
        sopsFile = ../../../secrets/default.yaml;
        key = "nextcloud/database_password";
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
        restartUnits = [ "nextcloud-setup.service" ];
      };

      sops.secrets.nextcloud_redis_password = {
        sopsFile = ../../../secrets/default.yaml;
        key = "nextcloud/redis_password";
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
        restartUnits = [ "nextcloud-setup.service" ];
      };

      sops.secrets.nextcloud_oidc_client_secret = {
        sopsFile = ../../../secrets/default.yaml;
        key = "nextcloud/oidc_client_secret";
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
        restartUnits = [ "nextcloud-setup.service" ];
      };

      # Nextcloud configuration
      services.nextcloud = {
        enable = true;

        # Use Nextcloud 31
        package = pkgs.nextcloud31;

        # Basic settings
        hostName = hostNameEffective;
        datadir = cfg.nextcloud.storage.dataDir;

        # Admin configuration using files for security
        config = {
          adminuser = "admin";
          adminpassFile = config.sops.secrets.nextcloud_admin_password.path;
          dbpassFile = config.sops.secrets.nextcloud_database_password.path;
          
          # Database configuration
          dbtype = if cfg.database.type == "postgresql" then "pgsql" else cfg.database.type;
          dbhost = "${cfg.database.host}:${toString cfg.database.port}";
          dbname = cfg.database.name;
          dbuser = cfg.database.user;
        };

        # HTTPS settings - disabled since we're behind Caddy
        https = false;


        # Auto-update
        autoUpdateApps = {
          enable = true;
          startAt = "05:00:00";
        };

        # Enable OIDC app
        extraApps = {
          user_oidc = pkgs.nextcloud31Packages.apps.user_oidc;
        };
        
        # Enable the extra apps
        extraAppsEnable = true;

        # Extra settings
        settings = {
          # Trusted domains
          trusted_domains = [ hostNameEffective "127.0.0.1" "cloud.nixmox.lan" ];
          
          # Reverse proxy configuration
          overwriteprotocol = "https";
          trusted_proxies = [ "192.168.99.14" ];  # Caddy proxy IP

          # Allow calls to local/private addresses (needed for OIDC to Authentik on LAN)
          allow_local_remote_servers = true;

          # Performance and security settings
          "opcache.enable" = "1";
          "opcache.enable_cli" = "1";
          "opcache.memory_consumption" = "128";
          "opcache.interned_strings_buffer" = "8";
          "opcache.max_accelerated_files" = "4000";
          "opcache.revalidate_freq" = "2";
          "opcache.fast_shutdown" = "1";

          # Disable App Store to avoid permission issues during setup
          "appstoreenabled" = "false";

          # Redis configuration (temporarily disabled for testing)
          # "redis.host" = cfg.redis.host;
          # "redis.port" = toString cfg.redis.port;
          # "redis.password" = config.sops.placeholder.nextcloud_redis_password;

          # OIDC configuration for Authentik (using user_oidc app)
          
          # Enable user_oidc app
          "user_oidc" = {
            "auto_provision" = true;
            "soft_auto_provision" = true;
            "httpclient.allowselfsigned" = true;
          };
          
          # OIDC provider configuration is managed through the web UI
          # The user_oidc app handles the provider configuration in the database
        };
        
      };


      # Redis configuration for Nextcloud caching
      services.redis.servers."".enable = lib.mkIf cfg.redis.enable true;
      services.redis.servers."".port = lib.mkIf cfg.redis.enable cfg.redis.port;
      # services.redis.servers."".requirePassFile = lib.mkIf cfg.redis.enable config.sops.secrets.nextcloud_redis_password.path;
      services.redis.servers."".settings = lib.mkIf cfg.redis.enable {
        maxmemory = "256mb";
        maxmemory-policy = "allkeys-lru";
        save = lib.mkForce "900 1 300 10 60 10000";
      };

      # Systemd service to configure OIDC provider (database-only approach)
      systemd.services.nextcloud-oidc-setup = {
        description = "Configure Nextcloud OIDC provider";
        after = [ "nextcloud-setup.service" "sops-nix.service" ];
        wants = [ "nextcloud-setup.service" "sops-nix.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          WorkingDirectory = "/var/lib/nextcloud";
          ExecStart = pkgs.writeShellScript "nextcloud-oidc-setup" ''
            set -euo pipefail
            
            # Wait for Nextcloud to be ready
            sleep 10
            
            # Install user_oidc app if not already installed
            /run/current-system/sw/bin/nextcloud-occ app:install user_oidc || true
            
            # Configure OIDC provider (stores in database, not config.php)
            /run/current-system/sw/bin/nextcloud-occ user_oidc:provider "Authentik" \
              --clientid="${cfg.oidc.clientId}" \
              --clientsecret="$(cat ${config.sops.secrets.nextcloud_oidc_client_secret.path})" \
              --discoveryuri="https://${cfg.oidc.authentikDomain}/application/o/${cfg.oidc.providerPath}/.well-known/openid-configuration" \
              --scope="${lib.concatStringsSep " " cfg.oidc.scopes}" \
              --mapping-uid="${cfg.oidc.usernameClaim}" \
              --mapping-groups="${cfg.oidc.groupsClaim}" \
              --unique-uid=0 \
              --no-interaction || true
          '';
          Restart = "on-failure";
          RestartSec = "30s";
        };
      };

      # Provide Nextcloud-specific Caddy configuration via global option
      # This will be collected by the Caddy module when it's enabled
      services.nixmox.caddyServiceConfigs.nextcloud = {
        extraConfig = ''
          # Nextcloud-specific configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
          
          # Nextcloud file upload size limits
          request_body {
            max_size 10GB
          }
          
          # Timeout settings for large file uploads
          timeouts {
            read_body 10m
            read_header 30s
            write 10m
            idle 5m
          }
        '';
        
        proxyConfig = ''
          # Nextcloud-specific proxy settings
          header_up X-Real-IP {remote}
          header_up X-Forwarded-Ssl on
          # Timeout settings for large file uploads
          timeout 10m
        '';
      };

      # Firewall rules - only allow local access since we're behind Caddy
      networking.firewall = {
        allowedTCPPorts = [
          cfg.nextcloud.port  # Nextcloud backend (behind Caddy)
        ] ++ lib.optional cfg.redis.enable cfg.redis.port;  # Redis if enabled
      };

      # Add host entries for external services
      networking.hosts = {
        "127.0.0.1" = [ hostNameEffective ];
      } // lib.optionalAttrs (cfg.database.host != "localhost") {
        "${cfg.database.host}" = [ "postgresql.nixmox.lan" ];
      };

      # Systemd service dependencies
      systemd.services.nextcloud-setup = {
        after = [ "run-secrets.d.mount" "network-online.target" ];
        wants = [ "run-secrets.d.mount" "network-online.target" ];
        # Add a simple delay to ensure network is ready
        preStart = ''
          echo "Waiting for network to be ready..."
          sleep 5
          echo "Starting Nextcloud setup..."
        '';
      };

    });
  } 