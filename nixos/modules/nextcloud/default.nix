{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.nextcloud;
in {
  options.services.nixmox.nextcloud = {
    enable = mkEnableOption "Nextcloud file sharing platform";

    subdomain = mkOption {
      type = types.str;
      default = "nextcloud";
      description = "Subdomain for Nextcloud; full host becomes <subdomain>.<services.nixmox.domain>";
    };

    hostName = mkOption {
      type = types.str;
      default = "";
      description = "Public host name for Nextcloud; defaults to <subdomain>.<services.nixmox.domain>";
    };

    # Database configuration
    database = {
      type = mkOption {
        type = types.enum [ "postgresql" "mysql" "sqlite" ];
        default = "postgresql";
        description = "Database type to use";
      };

      host = mkOption {
        type = types.str;
        default = "postgresql.nixmox.lan";
        description = "Database host";
      };

      port = mkOption {
        type = types.int;
        default = 5432;
        description = "Database port";
      };

      name = mkOption {
        type = types.str;
        default = "nextcloud";
        description = "Database name";
      };

      user = mkOption {
        type = types.str;
        default = "nextcloud";
        description = "Database user";
      };
      
      password = mkOption {
        type = types.str;
        default = "changeme";
        description = "Database password (should be overridden via SOPS)";
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
        default = "redis.nixmox.lan";
        description = "Redis host";
      };

      port = mkOption {
        type = types.int;
        default = 6379;
        description = "Redis port";
      };

      password = mkOption {
        type = types.str;
        default = "changeme";
        description = "Redis password (should be overridden via SOPS)";
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
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${config.services.nixmox.domain}";
    in {
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
          adminpassFile = "/run/secrets/nextcloud-admin-password";
          dbpassFile = "/run/secrets/nextcloud-db-password";
          
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

        # Extra settings
        settings = {
          # Trusted domains
          trusted_domains = [ hostNameEffective "127.0.0.1" ];

          # Performance and security settings
          "opcache.enable" = "1";
          "opcache.enable_cli" = "1";
          "opcache.memory_consumption" = "128";
          "opcache.interned_strings_buffer" = "8";
          "opcache.max_accelerated_files" = "4000";
          "opcache.revalidate_freq" = "2";
          "opcache.fast_shutdown" = "1";

          # Authentik integration (will be configured later)
          "auth_type" = "oauth2";
          "oauth2_provider_url" = if config.services.nixmox ? authentik && config.services.nixmox.authentik.enable
                                   then "https://${config.services.nixmox.authentik.domain}"
                                   else "https://authentik.nixmox.lan";
          "oauth2_client_id" = "nextcloud";
          "oauth2_client_secret" = "changeme"; # Should be overridden via SOPS
        };
      };

      # Firewall rules - only allow local access since we're behind Caddy
      networking.firewall = {
        allowedTCPPorts = [
          cfg.nextcloud.port  # Nextcloud backend (behind Caddy)
        ];
      };

      # Add host entries for external services
      networking.hosts = {
        "127.0.0.1" = [ hostNameEffective ];
      } // mkIf (cfg.database.host != "localhost") {
        "${cfg.database.host}" = [ "postgresql.nixmox.lan" ];
      } // mkIf (cfg.redis.host != "localhost") {
        "${cfg.redis.host}" = [ "redis.nixmox.lan" ];
      };

      # SOPS secrets for Nextcloud (temporarily disabled for testing)
      # sops.secrets = {
      #   "nextcloud-admin-password" = {
      #     owner = "nextcloud";
      #     group = "nextcloud";
      #     mode = "0400";
      #     restartUnits = [ "nextcloud-setup.service" ];
      #   };
      # 
      #   "nextcloud-db-password" = {
      #     owner = "nextcloud";
      #     group = "nextcloud";
      #     mode = "0400";
      #     restartUnits = [ "nextcloud-setup.service" ];
      #   };
      # };
    });
  } 