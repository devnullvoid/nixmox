{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.nextcloud;
in {
  options.services.nixmox.nextcloud = {
    enable = mkEnableOption "Nextcloud file sharing platform";

    domain = mkOption {
      type = types.str;
      default = "nextcloud.nixmox.lan";
      description = "Domain for Nextcloud service";
    };

    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for services";
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
      hostName = mkOption {
        type = types.str;
        default = "nextcloud.nixmox.lan";
        description = "Nextcloud hostname";
      };

      port = mkOption {
        type = types.int;
        default = 80;
        description = "Nextcloud web interface port";
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

  config = mkIf cfg.enable {
    # Nextcloud configuration
    services.nextcloud = {
      enable = true;

      # Use Nextcloud 31
      package = pkgs.nextcloud31;

      # Basic settings
      hostName = cfg.nextcloud.hostName;
      datadir = cfg.nextcloud.storage.dataDir;

      # Admin configuration using files for security
      config = {
        adminuser = cfg.nextcloud.adminUser;
        adminpassFile = "/run/secrets/nextcloud-admin-password";
        dbtableprefix = "oc_";
        dbtype = if cfg.database.type == "postgresql" then "pgsql" else cfg.database.type;
        dbname = cfg.database.name;
        dbhost = if cfg.database.type == "postgresql" then "${cfg.database.host}:${toString cfg.database.port}" else cfg.database.host;
        dbuser = cfg.database.user;
        dbpassFile = "/run/secrets/nextcloud-db-password";
      };

      # HTTPS settings
      https = true;

      # Auto-update
      autoUpdateApps = {
        enable = true;
        startAt = "05:00:00";
      };

      # Redis configuration
      configureRedis = cfg.redis.enable;

      # Extra settings
      settings = {
        # Trusted domains
        trusted_domains = [ cfg.nextcloud.hostName ];

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
        "oauth2_provider_url" = "https://authentik.nixmox.lan";
        "oauth2_client_id" = "nextcloud";
        "oauth2_client_secret" = "changeme"; # Should be overridden via SOPS
      };

      # PHP options
      phpOptions = {
        "upload_max_filesize" = lib.mkForce "10G";
        "post_max_size" = lib.mkForce "10G";
        "max_execution_time" = lib.mkForce "3600";
        "max_input_time" = lib.mkForce "3600";
        "memory_limit" = lib.mkForce "512M";
      };
    };

    # Redis for Nextcloud (if enabled and local)
    services.redis.servers.nextcloud = mkIf (cfg.redis.enable && cfg.redis.host == "localhost") {
      enable = true;
      settings = {
        # Security
        requirepass = cfg.redis.password;

        # Performance
        maxmemory = "256mb";

        # Persistence
        save = [ "900 1" "300 10" "60 10000" ];
      };
    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        80   # HTTP
        443  # HTTPS
      ];
    };

    # Add host entries for external services
    networking.hosts = mkIf (cfg.database.host != "localhost") {
      "${cfg.database.host}" = [ "postgresql.nixmox.lan" ];
    } // mkIf (cfg.redis.host != "localhost") {
      "${cfg.redis.host}" = [ "redis.nixmox.lan" ];
    };
  };
} 