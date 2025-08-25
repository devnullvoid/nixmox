{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.postgresql;
in {
  options.services.nixmox.postgresql = {
    enable = mkEnableOption "PostgreSQL database server";

    # PostgreSQL configuration
    port = mkOption {
      type = types.int;
      default = 5432;
      description = "PostgreSQL port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/postgresql";
      description = "PostgreSQL data directory";
    };

    # Database configurations for different services
    databases = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Database name";
          };
          owner = mkOption {
            type = types.str;
            description = "Database owner";
          };
          extensions = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "PostgreSQL extensions to enable";
          };
        };
      });
      default = {};
      description = "Databases to create";
    };

    # User configurations
    users = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Username";
          };
          password = mkOption {
            type = types.str;
            default = "changeme";
            description = "User password (should be overridden via SOPS)";
          };
          databases = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Databases this user can access";
          };
          superuser = mkOption {
            type = types.bool;
            default = false;
            description = "Whether this user is a superuser";
          };
        };
      });
      default = {};
      description = "PostgreSQL users to create";
    };
  };

  config = mkIf cfg.enable {
    # SOPS secrets for PostgreSQL
    sops.secrets = {
      "authentik/postgresql_password" = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [ "postgresql.service" ];
      };
    };
    
    # PostgreSQL configuration
    services.postgresql = {
      enable = true;
      dataDir = cfg.dataDir;
      settings = {
        port = cfg.port;
        
        # Network settings - allow remote connections
        listen_addresses = lib.mkForce "*";
        
        # Connection pooling settings
        max_connections = 200;  # Increased from default 100
        superuser_reserved_connections = 3;
        
        # Connection timeout settings
        tcp_keepalives_idle = 600;
        tcp_keepalives_interval = 30;
        tcp_keepalives_count = 3;
        
        # Idle connection timeout
        idle_in_transaction_session_timeout = "300s";
        
        # Performance settings
        # Memory settings
        shared_buffers = "256MB";
        effective_cache_size = "1GB";
        maintenance_work_mem = "64MB";
        
        # WAL settings
        checkpoint_completion_target = "0.9";
        wal_buffers = "16MB";
        min_wal_size = "1GB";
        max_wal_size = "4GB";
        
        # Query optimization
        default_statistics_target = "100";
        random_page_cost = "1.1";
        effective_io_concurrency = "200";
        work_mem = "4MB";
        
        # Connection settings
        
        # Logging
        log_statement = "all";
        log_min_duration_statement = "1000";
        log_checkpoints = "on";
        log_connections = "on";
        log_disconnections = "on";
        log_lock_waits = "on";
        log_temp_files = "0";
      };

      # Enable required extensions
      enableJIT = true;
      package = pkgs.postgresql_16;
      
      # Configure authentication for internal network
      authentication = ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             all                                     trust
        host    all             all             127.0.0.1/32            md5
        host    all             all             ::1/128                 md5
        # Allow connections from internal network (192.168.99.0/24)
        host    all             all             192.168.99.0/24         md5
        # Allow connections from all hosts (for development - restrict in production)
        host    all             all             0.0.0.0/0               md5
      '';
      
      # Create databases
      ensureDatabases = mapAttrsToList (name: db: db.name) cfg.databases;

      # Create users
      ensureUsers = mapAttrsToList (name: user: {
        name = user.name;
        ensureDBOwnership = true;
      }) cfg.users;
      
      initialScript = pkgs.writeText "init.sql" ''
        -- Create users and databases dynamically
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: user: ''
          -- Create ${user.name} user
          CREATE USER ${user.name} WITH PASSWORD '${user.password}';
          ${lib.optionalString (user.databases != []) ''
            -- Create ${user.name} databases
            ${lib.concatStringsSep "\n" (map (db: ''
              CREATE DATABASE ${db} OWNER ${user.name};
              GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user.name};
            '') user.databases)}
          ''}
        '') cfg.users)}
        
        -- Enable required extensions for specific databases
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: db: ''
          ${lib.optionalString (db.extensions != []) ''
            -- Enable extensions for ${db.name}
            ${lib.concatStringsSep "\n" (map (ext: ''
              CREATE EXTENSION IF NOT EXISTS "${ext}";
            '') db.extensions)}
          ''}
        '') cfg.databases)}
      '';
      


    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # PostgreSQL
      ];
    };

    # Systemd services
    systemd.services = {
      postgresql = {
        after = [ "network.target" "postgresql-data-dir.service" ];
        wants = [ "postgresql-data-dir.service" ];
        wantedBy = [ "multi-user.target" ];
      };
      
      # Create PostgreSQL data directory
      postgresql-data-dir = {
        description = "Create PostgreSQL data directory";
        wantedBy = [ "multi-user.target" ];
        before = [ "postgresql.service" ];
        
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${cfg.dataDir}";
          ExecStartPost = [
            "${pkgs.coreutils}/bin/chown postgres:postgres ${cfg.dataDir}"
            "${pkgs.coreutils}/bin/chmod 700 ${cfg.dataDir}"
          ];
          RemainAfterExit = true;
        };
      };
    };

    # Health check service
    systemd.services.postgresql-health = {
      description = "PostgreSQL health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.postgresql_16}/bin/psql -h /var/run/postgresql -U postgres -d postgres -c 'SELECT 1;'";
        Restart = "on-failure";
        RestartSec = "30s";
        User = "postgres";
        Group = "postgres";
      };
    };
  };
}
