{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.postgresql;
  
  # Get all services from manifest (core + application services)
  allServices = (manifest.core_services or {}) // (manifest.services or {});
  
  # Extract additional databases from manifest
  # Services can declare additional databases in their interface.dbs.{service}.additionaldbs
  additionalDatabases = builtins.foldl' (acc: serviceName:
    let
      service = allServices.${serviceName} or {};
      serviceDbs = service.interface.dbs or {};
    in
      acc // (builtins.foldl' (dbAcc: dbName:
        let
          dbConfig = serviceDbs.${dbName} or {};
          additionalDbs = dbConfig.additionaldbs or [];
        in
          dbAcc // (builtins.foldl' (addAcc: addDbName:
            addAcc // {
              "${addDbName}" = {
                name = addDbName;
                owner = dbConfig.owner or dbName;
                extensions = [];
              };
            }
          ) {} additionalDbs)
      ) {} (builtins.attrNames serviceDbs))
  ) {} (builtins.attrNames allServices);
  
  # Extract database requirements directly from manifest
  # Collect all database configurations from all services
  manifestDatabases = builtins.foldl' (acc: serviceName:
    let
      service = allServices.${serviceName} or {};
      serviceDbs = service.interface.dbs or {};
    in
      acc // (builtins.mapAttrs (dbName: dbConfig: {
        name = dbConfig.name or dbName;
        owner = dbConfig.owner or dbName;
        extensions = dbConfig.extensions or [];
      }) serviceDbs)
  ) {} (builtins.attrNames allServices);
  
  # Merge manifest databases with automatically created additional databases
  allManifestDatabases = manifestDatabases // additionalDatabases;
  
  # Fix database names to match user names for services that expect this
  # This is needed for nixos-mailserver which expects database name to match user name
  fixedDatabases = builtins.mapAttrs (dbKey: dbConfig:
    if dbKey == "mail-mail" then
      # For mail service, use the user name as the database name
      dbConfig // { name = dbKey; }
    else
      dbConfig
  ) allManifestDatabases;
  
  # Generate user configurations from manifest (including log databases)
  manifestUsers = builtins.mapAttrs (dbKey: dbConfig:
    {
      name = dbConfig.owner or dbKey;
      # Password will come from SOPS secrets, not hardcoded
      databases = [ (dbConfig.name or dbKey) ];
      superuser = dbConfig.superuser or false;
    }
  ) allManifestDatabases;
  
  # Merge manifest values with manual overrides (manual takes precedence)
  finalDatabases = fixedDatabases // cfg.databases;
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
      # Include both core_services and services
      allServices = (manifest.core_services or {}) // (manifest.services or {});
      dbServices = lib.filterAttrs (name: service:
        service ? interface && (service.interface ? db || service.interface ? dbs)
      ) allServices;

      # Generate SOPS secret config for each database service
      # Handle both single db (interface.db) and multiple dbs (interface.dbs)
      dbSecrets = lib.foldl' (acc: serviceName:
        let
          service = allServices.${serviceName};
          dbInterface = service.interface.db or {};
          dbsInterface = service.interface.dbs or {};
          
          # Generate secrets for single db
          singleDbSecrets = if dbInterface != {} then {
            "${serviceName}/database_password" = {
              owner = "postgres";
              group = "postgres";
              mode = "0400";
              restartUnits = [ "postgresql-set-passwords.service" ];
            };
          } else {};
          
          # Generate secrets for multiple dbs
          multipleDbsSecrets = if dbsInterface != {} then
            lib.mapAttrs' (dbName: dbConfig: {
              name = "${serviceName}/${dbName}/database_password";
              value = {
                owner = "postgres";
                group = "postgres";
                mode = "0400";
                restartUnits = [ "postgresql-set-passwords.service" ];
              };
            }) dbsInterface
          else {};
        in
          acc // singleDbSecrets // multipleDbsSecrets
      ) {} (builtins.attrNames dbServices);

              # Add pgAdmin password and OIDC client secret
        pgAdminSecrets = {
          "postgresql/pgadmin_password" = {
            owner = "pgadmin";
            group = "pgadmin";
            mode = "0400";
          };
          "postgresql/oidc_client_secret" = {
            owner = "pgadmin";
            group = "pgadmin";
            mode = "0400";
          };
        };
        in
          dbSecrets // pgAdminSecrets;

        # Sops template for complete pgAdmin configuration with embedded secret
        sops.templates."pgadmin-config.py".content = ''
          # Standard pgAdmin settings
          DEFAULT_SERVER = "0.0.0.0"
          DEFAULT_SERVER_PORT = 5050
          SERVER_MODE = True
          MASTER_PASSWORD_REQUIRED = False
          WTF_CSRF_ENABLED = False
          SESSION_COOKIE_SECURE = False
          SESSION_COOKIE_HTTPONLY = True
          SESSION_COOKIE_SAMESITE = "Lax"
          SECURE_PROXY_SSL_HEADER = ["X-Forwarded-Proto", "https"]
          PREFERRED_URL_SCHEME = "https"
          UPGRADE_CHECK_ENABLED = False
          PASSWORD_LENGTH_MIN = 6
          
          # OAuth2 settings
          AUTHENTICATION_SOURCES = ["oauth2", "internal"]
          OAUTH2_AUTO_CREATE_USER = True
          OAUTH2_CONFIG = [ {
              "OAUTH2_NAME": "authentik",
              "OAUTH2_DISPLAY_NAME": "Login with Authentik",
              "OAUTH2_CLIENT_ID": "${manifest.core_services.postgresql.interface.auth.oidc.client_id}",
              "OAUTH2_CLIENT_SECRET": "${config.sops.placeholder."postgresql/oidc_client_secret"}",
              "OAUTH2_TOKEN_URL": "https://${manifest.core_services.authentik.interface.proxy.domain}/application/o/token/",
              "OAUTH2_AUTHORIZATION_URL": "https://${manifest.core_services.authentik.interface.proxy.domain}/application/o/authorize/",
              "OAUTH2_API_BASE_URL": "https://${manifest.core_services.authentik.interface.proxy.domain}/",
              "OAUTH2_USERINFO_ENDPOINT": "https://${manifest.core_services.authentik.interface.proxy.domain}/application/o/userinfo/",
              "OAUTH2_SERVER_METADATA_URL": "https://${manifest.core_services.authentik.interface.proxy.domain}/application/o/postgresql/.well-known/openid-configuration",
              "OAUTH2_SCOPE": "${builtins.concatStringsSep " " manifest.core_services.postgresql.interface.auth.oidc.scopes}",
              "OAUTH2_ICON": "fa-key",
              "OAUTH2_BUTTON_COLOR": "#1f2937",
              "OAUTH2_SSL_CERT_VERIFICATION": False
          } ]
        '';
        sops.templates."pgadmin-config.py".owner = "pgadmin";
        sops.templates."pgadmin-config.py".group = "pgadmin";
        sops.templates."pgadmin-config.py".mode = "0400";
    
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
        9187      # PostgreSQL exporter
        # pgAdmin port 5050 is handled by services.pgadmin.openFirewall
      ];
    };

    # Systemd services
    systemd.services = {
      postgresql = {
        after = [ "network.target" "postgresql-data-dir.service" "run-secrets.d.mount" ];
        wants = [ "postgresql-data-dir.service" "run-secrets.d.mount" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          # Mount SOPS secrets to make them available to PostgreSQL
          BindPaths = [
            "/run/secrets:/run/secrets:ro"
          ];
        };
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
          
          echo "Setting passwords for all database users..."
          
          # Set passwords for all database users from SOPS secrets
          # Dynamically discover services with database configurations from manifest
          cd /run/secrets
          for SERVICE_NAME in */; do
            # Remove trailing slash
            SERVICE_NAME=''${SERVICE_NAME%/}
            
            # Check if this service has a single database password secret
            SINGLE_DB_SECRET_PATH="/run/secrets/$SERVICE_NAME/database_password"
            if [ -f "$SINGLE_DB_SECRET_PATH" ]; then
              echo "Setting password for $SERVICE_NAME user (single db)..."
              PASSWORD=$(tr -d '\n' < "$SINGLE_DB_SECRET_PATH")
              echo "Password length: $(printf %s "$PASSWORD" | wc -c)"

              echo "Executing: ALTER USER $SERVICE_NAME WITH PASSWORD '***';"
              SQL_CMD="ALTER USER $SERVICE_NAME WITH PASSWORD '$PASSWORD';"
              ${pkgs.postgresql_16}/bin/psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U postgres -d postgres -c "$SQL_CMD"

              echo "Password set successfully for $SERVICE_NAME user"
            else
              # Check for multiple database secrets (SERVICE_NAME/DB_NAME/database_password)
              for DB_SECRET_PATH in /run/secrets/$SERVICE_NAME/*/database_password; do
                if [ -f "$DB_SECRET_PATH" ]; then
                  # Extract database name from path
                  DB_NAME=$(basename $(dirname "$DB_SECRET_PATH"))
                  echo "Setting password for $SERVICE_NAME-$DB_NAME user (multiple dbs)..."
                  PASSWORD=$(tr -d '\n' < "$DB_SECRET_PATH")
                  echo "Password length: $(printf %s "$PASSWORD" | wc -c)"

                  echo "Executing: ALTER USER $SERVICE_NAME-$DB_NAME WITH PASSWORD '***';"
                  SQL_CMD="ALTER USER $SERVICE_NAME-$DB_NAME WITH PASSWORD '$PASSWORD';"
                  ${pkgs.postgresql_16}/bin/psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U postgres -d postgres -c "$SQL_CMD"

                  echo "Password set successfully for $SERVICE_NAME-$DB_NAME user"
                fi
              done
            fi
          done
          
          echo "All database passwords have been set"
        '';
        Restart = "on-failure";
        RestartSec = "30s";
        User = "postgres";
        Group = "postgres";
      };
    };

    # PostgreSQL Exporter for monitoring
    services.prometheus.exporters.postgres = {
      enable = true;
      port = 9187;
      # Use Unix socket connection with peer authentication (no password needed)
      dataSourceName = "postgresql:///postgres?host=/run/postgresql";
      # Run as postgres user to use peer authentication
      user = "postgres";
      group = "postgres";
    };

    # Create custom pgAdmin configuration file with embedded secrets
    environment.etc."pgadmin/config_system.py".source = lib.mkForce config.sops.templates."pgadmin-config.py".path;

    # pgAdmin web interface using official NixOS module
    services.pgadmin = {
      enable = true;
      port = 5050;
      openFirewall = true;
      initialEmail = "admin@nixmox.lan";
      initialPasswordFile = config.sops.secrets."postgresql/pgadmin_password".path;
      # Disable the built-in configuration generation
      settings = lib.mkForce {};
    };

    # Override pgAdmin systemd service to set SSL environment variables and OIDC secret
    systemd.services.pgadmin = {
      environment = {
        # Disable SSL verification for OIDC requests (temporary workaround)
        PYTHONHTTPSVERIFY = "0";
        REQUESTS_CA_BUNDLE = "";
        SSL_CERT_FILE = "";
        # Additional SSL bypass variables
        CURL_INSECURE = "1";
        # OIDC client secret from SOPS file
        PGADMIN_OIDC_CLIENT_SECRET = "$(cat ${config.sops.secrets."postgresql/oidc_client_secret".path})";
      };
    };




  };
}
