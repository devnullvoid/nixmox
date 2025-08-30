{ config, pkgs, lib, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.guacamole;
  
  # Get guacamole service configuration from manifest
  guacamoleConfig = (manifest.services or {}).guacamole or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get core services for dependencies
  coreServices = manifest.core_services or {};
  
  # Derive configuration from manifest
  manifestConfig = {
    # Extract subdomain from proxy.domain (e.g., "guac.nixmox.lan" -> "guac")
    subdomain = if guacamoleConfig.interface.proxy.domain or "" != "" then
      (builtins.head (builtins.split "\\." (guacamoleConfig.interface.proxy.domain or "")))
    else
      "guac";
    
    # Use proxy.domain from manifest
    hostName = guacamoleConfig.interface.proxy.domain or "guac.${baseDomain}";
    
    # Use authentik domain from manifest
    authentikDomain = (coreServices.authentik.interface.proxy.domain or "auth.${baseDomain}");
    
    # Use OIDC provider path from manifest (default to service name)
    oidcProviderPath = "guacamole";
    
    # Use client ID from manifest
    clientId = guacamoleConfig.interface.auth.oidc.client_id or "guacamole-client";
    
    # Use database configuration from manifest
    database = {
      host = guacamoleConfig.interface.db.host or coreServices.postgresql.ip or "postgresql.${baseDomain}";
      port = guacamoleConfig.interface.db.port or 5432;
      name = guacamoleConfig.interface.db.name or "guacamole";
      user = guacamoleConfig.interface.db.user or "guacamole";
      # Password will come from SOPS database_password secret
      password = "CHANGEME";
    };
    
    # Bootstrap admin user configuration
    bootstrapAdmin = {
      enable = true;
      username = "akadmin";  # This will be the OIDC admin username
      password = null;       # Generate a random password (for local auth fallback)
    };
  };

  guacVer = config.services.guacamole-client.package.version;
  pgVer = "42.7.4";

  pgDriverSrc = pkgs.fetchurl {
    url = "https://jdbc.postgresql.org/download/postgresql-${pgVer}.jar";
    sha256 = "sha256-GIl2ch6tjoYn622DidUA3MwMm+vYhSaKMEcYAnSmAx4=";
  };

  pgExtension = pkgs.stdenv.mkDerivation {
    name = "guacamole-auth-jdbc-postgresql-${guacVer}";
    src = pkgs.fetchurl {
      url = "https://dlcdn.apache.org/guacamole/${guacVer}/binary/guacamole-auth-jdbc-${guacVer}.tar.gz";
      sha256 = "sha256-l7xf09Z9JcDpikddHf0wigN4WfVJ+sRxcccjt6cDk2Y=";
    };
    phases = "unpackPhase installPhase";
    unpackPhase = ''
      tar -xzf $src
    '';
    installPhase = ''
      mkdir -p $out
      cp -r guacamole-auth-jdbc-${guacVer}/postgresql/* $out
    '';
  };

  oidcExtension = pkgs.stdenv.mkDerivation {
    name = "guacamole-auth-sso-openid-${guacVer}";
    src = pkgs.fetchurl {
      url = "https://dlcdn.apache.org/guacamole/${guacVer}/binary/guacamole-auth-sso-${guacVer}.tar.gz";
      sha256 = "sha256-6VeYRHGsUKh/Ry9Rrsm/fjeK5nziUC/5OAMAEaZw3K4=";
    };
    phases = "unpackPhase installPhase";
    unpackPhase = ''
      tar -xzf $src
    '';
    installPhase = ''
      mkdir -p $out
      cp guacamole-auth-sso-${guacVer}/openid/guacamole-auth-sso-openid-${guacVer}.jar $out
    '';
  };

  psql = "${pkgs.postgresql_16}/bin/psql";
  cat = "${pkgs.coreutils}/bin/cat";
  keytool = "${pkgs.openjdk}/bin/keytool";
in {
  imports = [
    # SOPS will be imported by the core module
    ../shared/internal-ca.nix
  ];

  options.services.nixmox.guacamole = {
    enable = mkEnableOption "Guacamole, a clientless remote desktop gateway";

    subdomain = mkOption {
      type = types.str;
      default = manifestConfig.subdomain;
      description = "Subdomain for Guacamole; full host becomes <subdomain>.<services.nixmox.domain> unless overridden by hostName";
    };

    hostName = mkOption {
      type = types.str;
      default = manifestConfig.hostName;
      description = "Public host name for Guacamole; defaults to <subdomain>.<services.nixmox.domain>";
    };

    # Authentik domain for OIDC
    authentikDomain = mkOption {
      type = types.str;
      default = manifestConfig.authentikDomain;
      description = "Authentik domain used for OIDC endpoints";
    };

    # OIDC provider path (e.g., "guacamole" for /application/o/guacamole/)
    oidcProviderPath = mkOption {
      type = types.str;
      default = manifestConfig.oidcProviderPath;
      description = "OIDC provider path in Authentik (used for jwks and issuer endpoints)";
    };

    clientId = mkOption {
      type = types.str;
      default = manifestConfig.clientId;
      description = "OIDC client ID to use for Guacamole (public value)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall for Guacamole Tomcat port (normally unnecessary behind Caddy)";
    };

    tomcatPort = mkOption {
      type = types.int;
      default = 8280;
      description = "Tomcat port hosting Guacamole client";
    };

    # Database configuration
    database = {
      host = mkOption {
        type = types.str;
        default = manifestConfig.database.host;
        description = "PostgreSQL host";
      };
      
      port = mkOption {
        type = types.int;
        default = manifestConfig.database.port;
        description = "PostgreSQL port";
      };
      
      name = mkOption {
        type = types.str;
        default = manifestConfig.database.name;
        description = "PostgreSQL database name";
      };
      
      user = mkOption {
        type = types.str;
        default = manifestConfig.database.user;
        description = "PostgreSQL username";
      };
      
      password = mkOption {
        type = types.str;
        default = manifestConfig.database.password;
        description = "PostgreSQL password (should be overridden via SOPS)";
      };
    };

    bootstrapAdmin = {
      enable = mkOption {
        type = types.bool;
        default = manifestConfig.bootstrapAdmin.enable;
        description = "Create or update a local Guacamole DB admin matching the given username";
      };
      username = mkOption {
        type = types.str;
        default = manifestConfig.bootstrapAdmin.username;
        description = "Username to bootstrap as Guacamole admin (should match Authentik preferred_username)";
      };
      password = mkOption {
        type = types.nullOr types.str;
        default = manifestConfig.bootstrapAdmin.password;
        description = "Optional password for the local admin; random if null. Not used for OIDC but stored for completeness.";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${config.services.nixmox.domain}";
    in {

    # Database password secret (for PostgreSQL module)
    sops.secrets.guacamole_database_password = {
      sopsFile = ../../../secrets/default.yaml;
      key = "guacamole/database_password";
      mode = "0400";
    };

    # Add PostgreSQL client tools for database schema import
    environment.systemPackages = with pkgs; [
      postgresql
    ];

    # Ensure local resolution works even before DNS is in place
    networking.hosts."127.0.0.1" = [ hostNameEffective ];

    # Optionally open the Tomcat port (usually proxied locally by Caddy)
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.tomcatPort ];

    # Guacamole services
    services.guacamole-server.enable = true;
    services.guacamole-client.enable = true;

    # Host the client on Tomcat, avoid common 8080 clashes
    services.tomcat.port = cfg.tomcatPort;

    # Render guacamole.properties via sops template; avoid duplicating settings
    sops.templates.guacamole_properties = {
      # Write the final config where Tomcat will read it via GUACAMOLE_HOME
      path = "/etc/guacamole/guacamole.properties";
      owner = "tomcat";
      group = "tomcat";
      mode = "0400";
      # Restart Tomcat when the rendered template changes
      restartUnits = [ "tomcat.service" ];
      content = ''
        # Generated with sops-nix
        extension-priority = openid
        guacd-hostname = localhost
        guacd-port = ${toString config.services.guacamole-server.port}
        
        openid-authorization-endpoint = https://${cfg.authentikDomain}/application/o/authorize/
        openid-jwks-endpoint = https://${cfg.authentikDomain}/application/o/${cfg.oidcProviderPath}/jwks/
        openid-issuer = https://${cfg.authentikDomain}/application/o/${cfg.oidcProviderPath}/
        openid-client-id = ${cfg.clientId}
        openid-redirect-uri = https://${hostNameEffective}/guacamole/
        openid-username-claim-type = preferred_username
        openid-scope = openid email profile
        openid-allowed-redirect-uris = https://${hostNameEffective}/guacamole/
        openid-validate-token = true
        openid-max-token-length = 8192

        postgresql-database = ${cfg.database.name}
        postgresql-hostname = ${cfg.database.host}
        postgresql-port = ${toString cfg.database.port}
        postgresql-username = ${cfg.database.user}
        # Embed secret via sops-nix placeholder; replaced at activation
        postgresql-password = ${config.sops.placeholder.guacamole_database_password}
      '';
    };

    # Provide required extensions and JDBC driver
    environment.etc."guacamole/extensions/guacamole-auth-sso-openid-${guacVer}.jar".source = "${oidcExtension}/guacamole-auth-sso-openid-${guacVer}.jar";
    environment.etc."guacamole/lib/postgresql-${pgVer}.jar".source = pgDriverSrc;
    environment.etc."guacamole/extensions/guacamole-auth-jdbc-postgresql-${guacVer}.jar".source = "${pgExtension}/guacamole-auth-jdbc-postgresql-${guacVer}.jar";

    # Remove runtime copy/generation; rely on GUACAMOLE_HOME=/etc/guacamole and sops template


    # Note: No local PostgreSQL configuration - using external database

    # Initialize Guacamole DB schema if empty (using external PostgreSQL)
    systemd.services.guacamole-pgsql-schema-import = {
      enable = true;
      after = [ "network.target" ];
      wantedBy = [ "tomcat.service" "multi-user.target" ];
      script = ''
        echo "[guacamole-bootstrapper] Info: testing database connectivity..."
        echo "Host: ${cfg.database.host}"
        echo "Port: ${toString cfg.database.port}"
        echo "User: ${cfg.database.user}"
        echo "Database: ${cfg.database.name}"

        # Read database password directly from SOPS-managed file
        export PGPASSWORD="$(<${config.sops.secrets.guacamole_database_password.path})"
        
        # Test basic connectivity first
        ${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -U ${cfg.database.user} -d ${cfg.database.name} -c "SELECT 1 as test;" || {
          echo "Database connection failed"
          exit 1
        }
        
        echo "Database connection successful"
        
        # Check if database is empty
        output=$(${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -U ${cfg.database.user} -d ${cfg.database.name} -c "\\dt" 2>&1)
        if [[ "$output" == *"Did not find any relations."* ]]; then
          echo "[guacamole-bootstrapper] Info: installing guacamole postgres database schema..."
          ${cat} ${pgExtension}/schema/*.sql | ${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -U ${cfg.database.user} -d ${cfg.database.name} -f -
        else
          echo "Database already has tables, skipping schema import"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
      };
    };

    # Ensure Tomcat starts after network and config generation
    systemd.services.tomcat = {
      after = [ "network.target" ];
      serviceConfig = {
        Environment = [
          "GUACAMOLE_HOME=/etc/guacamole"
        ];
        ExecStartPre = [
          "${pkgs.coreutils}/bin/mkdir -p /etc/guacamole"
          # Import internal CA into a Java truststore so Guacamole trusts Authentik TLS (ignore failures)
          "${pkgs.bash}/bin/bash -lc '${keytool} -importcert -trustcacerts -alias nixmox-internal-ca -file /var/lib/shared-certs/internal-ca.crt -keystore /etc/guacamole/java-cacerts -storepass changeit -noprompt || true'"
          "${pkgs.bash}/bin/bash -lc 'test -f /etc/guacamole/java-cacerts && chown tomcat:tomcat /etc/guacamole/java-cacerts || true'"
          "${pkgs.bash}/bin/bash -lc 'test -f /etc/guacamole/java-cacerts && chmod 600 /etc/guacamole/java-cacerts || true'"
        ];
      };
    };

    # Point Tomcat/Java at the truststore containing our local CA
    services.tomcat.javaOpts = [
      "-Djavax.net.ssl.trustStore=/etc/guacamole/java-cacerts"
      "-Djavax.net.ssl.trustStorePassword=changeit"
    ];

    # Bootstrap a local Guacamole admin user if requested
    systemd.services.guacamole-bootstrap-admin = mkIf cfg.bootstrapAdmin.enable {
      description = "Bootstrap Guacamole admin user and rename guacadmin to akadmin";
      requires = [ "guacamole-pgsql-schema-import.service" ];
      after = [ "guacamole-pgsql-schema-import.service" ];
      wantedBy = [ "tomcat.service" "multi-user.target" ];
      environment = {
        GUAC_BOOTSTRAP_USER = cfg.bootstrapAdmin.username;
        GUAC_BOOTSTRAP_PASS = if cfg.bootstrapAdmin.password == null then "" else cfg.bootstrapAdmin.password;
      };
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail
        if [ -z "''${GUAC_BOOTSTRAP_USER}" ]; then
          echo "[guacamole-bootstrap-admin] Skipping: no username provided" >&2
          exit 0
        fi

        echo "[guacamole-bootstrap-admin] Starting Guacamole admin user setup..."

        # Read database password directly from SOPS-managed file
        export PGPASSWORD="$(<${config.sops.secrets.guacamole_database_password.path})"
        # Step 1: Rename existing guacadmin user to akadmin if it exists
        echo "[guacamole-bootstrap-admin] Checking for existing guacadmin user..."
        EXISTING_GUACADMIN=$(${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -t -A \
          -U ${cfg.database.user} -d ${cfg.database.name} -c "
        SELECT COUNT(*) FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER';
        " | tr -d ' ')
        
        if [ "$EXISTING_GUACADMIN" -gt 0 ]; then
          echo "[guacamole-bootstrap-admin] Found existing guacadmin user, renaming to akadmin..."
          ${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -v ON_ERROR_STOP=1 \
            -U ${cfg.database.user} -d ${cfg.database.name} -c "
          UPDATE guacamole_entity 
          SET name = 'akadmin' 
          WHERE name = 'guacadmin' AND type = 'USER';
          "
          echo "[guacamole-bootstrap-admin] Successfully renamed guacadmin to akadmin"
        else
          echo "[guacamole-bootstrap-admin] No existing guacadmin user found"
        fi

        # Step 2: Check if akadmin user already exists
        echo "[guacamole-bootstrap-admin] Checking if akadmin user exists..."
        EXISTING_AKADMIN=$(${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -t -A \
          -U ${cfg.database.user} -d ${cfg.database.name} -c "
        SELECT COUNT(*) FROM guacamole_entity WHERE name = 'akadmin' AND type = 'USER';
        " | tr -d ' ')
        
        if [ "$EXISTING_AKADMIN" -gt 0 ]; then
          echo "[guacamole-bootstrap-admin] akadmin user already exists, ensuring admin permissions..."
          
          # Ensure admin permissions exist
          ${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -v ON_ERROR_STOP=1 \
            -U ${cfg.database.user} -d ${cfg.database.name} -c "
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'ADMINISTER'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_CONNECTION'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_CONNECTION_GROUP'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_SHARING_PROFILE'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_USER'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_USER_GROUP'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          "
          
          echo "[guacamole-bootstrap-admin] akadmin user permissions verified"
        else
          echo "[guacamole-bootstrap-admin] Creating new akadmin user..."
          
          # Generate salt and hash for password (if needed for local auth fallback)
          PASS=''${GUAC_BOOTSTRAP_PASS}
          if [ -z "$PASS" ]; then
            PASS=$(${pkgs.openssl}/bin/openssl rand -base64 18)
            echo "[guacamole-bootstrap-admin] Generated random password: $PASS"
          fi
          SALT=$(${pkgs.openssl}/bin/openssl rand -base64 32)
          HASH=$(printf "%s" "$SALT$PASS" | ${pkgs.openssl}/bin/openssl dgst -sha256 -binary | ${pkgs.coreutils}/bin/base64)
          
          # Create new akadmin user
          ${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -v ON_ERROR_STOP=1 \
            -U ${cfg.database.user} -d ${cfg.database.name} -c "
          INSERT INTO guacamole_entity (name, type) 
          VALUES ('akadmin', 'USER')
          ON CONFLICT (type, name) DO NOTHING;
          
          INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date, disabled, expired)
          SELECT e.entity_id, '$HASH', '$SALT', now(), false, false
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT (entity_id) 
          DO UPDATE SET 
            password_hash = EXCLUDED.password_hash,
            password_salt = EXCLUDED.password_salt,
            password_date = EXCLUDED.password_date;
          "
          
          # Grant admin permissions
          ${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -v ON_ERROR_STOP=1 \
            -U ${cfg.database.user} -d ${cfg.database.name} -c "
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'ADMINISTER'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_CONNECTION'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_CONNECTION_GROUP'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_SHARING_PROFILE'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_USER'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT e.entity_id, 'CREATE_USER_GROUP'
          FROM guacamole_entity e 
          WHERE e.name = 'akadmin' AND e.type = 'USER'
          ON CONFLICT DO NOTHING;
          "
          
          echo "[guacamole-bootstrap-admin] New akadmin user created with admin permissions"
        fi

        echo "[guacamole-bootstrap-admin] Admin user setup completed successfully"
      '';
    };

    # Enable internal CA for certificate trust
    services.nixmox.internalCa.enable = true;
    
    # Also enable wildcard key for HTTPS serving
    services.nixmox.internalCa.enableWildcardKey = true;
  });
}
