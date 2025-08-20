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
      
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/nextcloud";
        description = "Nextcloud data directory";
      };
      
      adminUser = mkOption {
        type = types.str;
        default = "admin";
        description = "Nextcloud admin username";
      };
      
      adminPassword = mkOption {
        type = types.str;
        default = "changeme";
        description = "Nextcloud admin password (should be overridden via SOPS)";
      };
      
      # Database configuration
      database = {
        type = mkOption {
          type = types.enum [ "sqlite" "postgresql" "mysql" ];
          default = "postgresql";
          description = "Database type for Nextcloud";
        };
        
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "Database host";
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
          description = "Enable Redis for Nextcloud";
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
        
        password = mkOption {
          type = types.str;
          default = "changeme";
          description = "Redis password (should be overridden via SOPS)";
        };
      };
      
      # Storage configuration
      storage = {
        dataDir = mkOption {
          type = types.str;
          default = "/var/lib/nextcloud/data";
          description = "Nextcloud data storage directory";
        };
        
        appsDir = mkOption {
          type = types.str;
          default = "/var/lib/nextcloud/apps";
          description = "Nextcloud apps directory";
        };
        
        configDir = mkOption {
          type = types.str;
          default = "/var/lib/nextcloud/config";
          description = "Nextcloud config directory";
        };
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
        dbtype = if cfg.nextcloud.database.type == "postgresql" then "pgsql" else cfg.nextcloud.database.type;
        dbname = cfg.nextcloud.database.name;
        dbhost = if cfg.nextcloud.database.type == "postgresql" then "localhost:/run/postgresql" else cfg.nextcloud.database.host;
        dbuser = cfg.nextcloud.database.user;
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
      configureRedis = cfg.nextcloud.redis.enable;
      
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
    
    # PostgreSQL for Nextcloud (if using PostgreSQL)
    services.postgresql = mkIf (cfg.nextcloud.database.type == "postgresql") {
      enable = true;
      
      # Create database and user
      ensureDatabases = [ cfg.nextcloud.database.name ];
      ensureUsers = [
        {
          name = cfg.nextcloud.database.user;
          ensureDBOwnership = true;
        }
      ];
      
      # Settings
      settings = {
        # Performance settings
        shared_buffers = "256MB";
        effective_cache_size = "1GB";
        maintenance_work_mem = "64MB";
        checkpoint_completion_target = "0.9";
        wal_buffers = "16MB";
        default_statistics_target = "100";
        random_page_cost = "1.1";
        effective_io_concurrency = "200";
        work_mem = "4MB";
        min_wal_size = "1GB";
        max_wal_size = "4GB";
      };
    };
    
    # Redis for Nextcloud (if enabled)
    services.redis.servers.nextcloud = mkIf cfg.nextcloud.redis.enable {
      enable = true;
      settings = {
        # Security
        requirepass = cfg.nextcloud.redis.password;
        
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
  };
} 