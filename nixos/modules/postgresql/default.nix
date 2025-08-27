{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.postgresql;
  
  # Get all services from manifest (core + application services)
  allServices = (manifest.core_services or {}) // (manifest.services or {});
  
  # Extract database requirements from services that have interface.db
  databaseRequirements = builtins.mapAttrs (serviceName: serviceConfig:
    serviceConfig.interface.db or {}
  ) (lib.filterAttrs (name: config: 
    builtins.hasAttr "db" (config.interface or {})
  ) allServices);
  
  # Generate database configurations from manifest
  manifestDatabases = builtins.mapAttrs (serviceName: dbConfig:
    {
      name = dbConfig.name or serviceName;
      owner = dbConfig.owner or serviceName;
      extensions = dbConfig.extensions or [];
    }
  ) databaseRequirements;
  
  # Generate user configurations from manifest
  manifestUsers = builtins.mapAttrs (serviceName: dbConfig:
    {
      name = dbConfig.owner or serviceName;
      # Password will come from SOPS secrets, not hardcoded
      databases = [ (dbConfig.name or serviceName) ];
      superuser = dbConfig.superuser or false;
    }
  ) databaseRequirements;
  
  # Merge manifest values with manual overrides (manual takes precedence)
  finalDatabases = manifestDatabases // cfg.databases;
  finalUsers = manifestUsers // cfg.users;
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
    # These can override manifest values if needed
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
      description = "Databases to create (can override manifest values)";
    };

    # User configurations
    # These can override manifest values if needed
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
      description = "PostgreSQL users to create (can override manifest values)";
    };
  };

  config = mkIf cfg.enable {
    # SOPS secrets for PostgreSQL - dynamically generated from manifest
    sops.secrets = let
      # Get all services that have a db interface from the manifest
      dbServices = lib.filterAttrs (name: service: 
        service ? interface && service.interface ? db
      ) (config._module.args.manifest.services or {});
      
      # Generate SOPS secret config for each database service
      dbSecrets = lib.mapAttrs' (name: service: {
        name = "${name}/database_password";
        value = {
          owner = "postgres";
          group = "postgres";
          mode = "0400";
          restartUnits = [ "postgresql-set-passwords.service" ];
        };
      }) dbServices;
      
      # Add authentik's special postgresql_password secret
      authentikSecret = {
        "authentik/postgresql_password" = {
          owner = "postgres";
          group = "postgres";
          mode = "0400";
          # When the secret changes, also re-run the password setter
          restartUnits = [ "postgresql.service" "postgresql-set-passwords.service" ];
        };
      };
    in
      authentikSecret // dbSecrets;
    
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
      
      # Configure authentication for internal network (override defaults)
      authentication = lib.mkForce ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             all                                     trust
        host    all             all             127.0.0.1/32            scram-sha-256
        host    all             all             ::1/128                 scram-sha-256
        # Allow connections from internal network (192.168.99.0/24)
        host    all             all             192.168.99.0/24         scram-sha-256
        # Allow connections from all hosts (for development - restrict in production)
        host    all             all             0.0.0.0/0               scram-sha-256
      '';
      
      # Create databases from manifest + manual overrides
      ensureDatabases = mapAttrsToList (name: db: db.name) finalDatabases;

      # Create users from manifest + manual overrides
      ensureUsers = mapAttrsToList (name: user: {
        name = user.name;
        ensureDBOwnership = true;
      }) finalUsers;
      
      initialScript = pkgs.writeText "init.sql" ''
        -- Create users and databases dynamically
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: user: ''
          -- Create ${user.name} user (password will be set by SOPS secrets)
          CREATE USER ${user.name};
          ${lib.optionalString (user.databases != []) ''
            -- Create ${user.name} databases
            ${lib.concatStringsSep "\n" (map (db: ''
              CREATE DATABASE ${db} OWNER ${user.name};
              GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user.name};
            '') user.databases)}
          ''}
        '') finalUsers)}
        
        -- Enable required extensions for specific databases
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: db: ''
          ${lib.optionalString (db.extensions != []) ''
            -- Enable extensions for ${db.name}
            ${lib.concatStringsSep "\n" (map (ext: ''
              CREATE EXTENSION IF NOT EXISTS "${ext}";
            '') db.extensions)}
          ''}
        '') finalDatabases)}
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
    
    # Service to set user passwords from SOPS secrets
    systemd.services.postgresql-set-passwords = {
      description = "Set PostgreSQL user passwords from SOPS secrets";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "run-secrets.d.mount" ];
      requires = [ "postgresql.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "set-passwords.sh" ''
          #!/bin/sh
          set -e
          
          # Wait for SOPS secret to be present (up to ~30s)
          for i in $(seq 1 30); do
            if [ -f "/run/secrets/authentik/postgresql_password" ]; then
              break
            fi
            sleep 1
          done

          # Set passwords for all users from SOPS secrets
          echo "Setting passwords for all database users..."
          
          # Dynamic password setting for all database services
          # This will automatically handle any new services added to the manifest
          for SECRET_PATH in /run/secrets/*/database_password; do
            if [ -f "$SECRET_PATH" ]; then
              # Extract service name from path (e.g., /run/secrets/vaultwarden/database_password -> vaultwarden)
              SERVICE_NAME=$(basename $(dirname "$SECRET_PATH"))
              
              # Skip if this is authentik (handled separately)
              if [ "$SERVICE_NAME" = "authentik" ]; then
                continue
              fi
              
              echo "Setting password for $SERVICE_NAME user..."
              PASSWORD=$(tr -d '\n' < "$SECRET_PATH")
              echo "Password length: $(printf %s "$PASSWORD" | wc -c)"
              
              echo "Executing: ALTER USER $SERVICE_NAME WITH PASSWORD '***';"
              SQL_CMD="ALTER USER $SERVICE_NAME WITH PASSWORD '$PASSWORD';"
              ${pkgs.postgresql_16}/bin/psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U postgres -d postgres -c "$SQL_CMD"
              
              echo "Password set successfully for $SERVICE_NAME user"
            fi
          done
          

          

          

          

          
          # Set Authentik user password from SOPS secrets (strip trailing newline)
          if [ -f "/run/secrets/authentik/postgresql_password" ]; then
            echo "Setting password for authentik user..."
            
            PASSWORD=$(tr -d '\n' < /run/secrets/authentik/postgresql_password)
            echo "Password length: $(printf %s "$PASSWORD" | wc -c)"
            
            echo "Executing: ALTER USER authentik WITH PASSWORD '***';"
            
            # Use proper shell variable handling to avoid escaping issues
            SQL_CMD="ALTER USER authentik WITH PASSWORD '$PASSWORD';"
            ${pkgs.postgresql_16}/bin/psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U postgres -d postgres -c "$SQL_CMD"
            
            # Check what was actually set in the database
            echo "Database password hash after setting:"
            ${pkgs.postgresql_16}/bin/psql -h /var/run/postgresql -U postgres -d postgres -c "SELECT rolname, substring(rolpassword,1,50) FROM pg_authid WHERE rolname='authentik';"
            
            LEN=$(printf %s "$PASSWORD" | wc -c)
            FP=$(printf %s "$PASSWORD" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-12)
            echo "Password set successfully for authentik user (len=$LEN, sha256_12=$FP)"
            
            # Test connection
            echo "Testing connection..."
            if PGPASSWORD="$PASSWORD" ${pkgs.postgresql_16}/bin/psql -h 127.0.0.1 -U authentik -d authentik -c 'SELECT 1;' >/dev/null 2>&1; then
              echo "Verified authentik login OK"
            else
              echo "Warning: authentik login verification failed"
            fi
          else
            echo "Warning: SOPS secret for authentik/postgresql_password not found"
          fi
          
          # Add more users here as needed
        '';
        Restart = "on-failure";
        RestartSec = "30s";
        User = "postgres";
        Group = "postgres";
      };
    };
  };
}
