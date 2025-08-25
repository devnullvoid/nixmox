{ inputs ? {}, lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.guacamole;

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
  options.services.nixmox.guacamole = {
    enable = mkEnableOption "Guacamole, a clientless remote desktop gateway";

    subdomain = mkOption {
      type = types.str;
      default = "guac";
      description = "Subdomain for Guacamole; full host becomes <subdomain>.<services.nixmox.domain> unless overridden by hostName";
    };

    hostName = mkOption {
      type = types.str;
      default = "";
      description = "Public host name for Guacamole; defaults to <subdomain>.<services.nixmox.domain>";
    };

    # Authentik domain for OIDC
    authentikDomain = mkOption {
      type = types.str;
      default = "authentik.nixmox.lan";
      description = "Authentik domain used for OIDC endpoints";
    };

    # OIDC provider path (e.g., "guacamole" for /application/o/guacamole/)
    oidcProviderPath = mkOption {
      type = types.str;
      default = "guacamole";
      description = "OIDC provider path in Authentik (used for jwks and issuer endpoints)";
    };

    clientId = mkOption {
      type = types.str;
      default = "guacamole-client";
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
        default = "postgresql.nixmox.lan";
        description = "PostgreSQL host";
      };
      
      port = mkOption {
        type = types.int;
        default = 5432;
        description = "PostgreSQL port";
      };
      
      name = mkOption {
        type = types.str;
        default = "guacamole";
        description = "PostgreSQL database name";
      };
      
      user = mkOption {
        type = types.str;
        default = "guacamole";
        description = "PostgreSQL username";
      };
      
      password = mkOption {
        type = types.str;
        default = "changeme";
        description = "PostgreSQL password (should be overridden via SOPS)";
      };
    };

    bootstrapAdmin = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Create or update a local Guacamole DB admin matching the given username";
      };
      username = mkOption {
        type = types.str;
        default = "";
        description = "Username to bootstrap as Guacamole admin (should match Authentik preferred_username)";
      };
      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional password for the local admin; random if null. Not used for OIDC but stored for completeness.";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${config.services.nixmox.domain}";
    in {

    # Ensure local resolution works even before DNS is in place
    networking.hosts."127.0.0.1" = [ hostNameEffective ];

    # Optionally open the Tomcat port (usually proxied locally by Caddy)
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.tomcatPort ];

    # Guacamole services
    services.guacamole-server.enable = true;
    services.guacamole-client.enable = true;

    # Host the client on Tomcat, avoid common 8080 clashes
    services.tomcat.port = cfg.tomcatPort;

    # Guacamole client settings (rendered by the upstream module)
    services.guacamole-client.settings = {
      guacd-hostname = "localhost";
      guacd-port = config.services.guacamole-server.port;
      extension-priority = "openid";

      # Database config - use external PostgreSQL
      postgresql-hostname = cfg.database.host;
      postgresql-port = cfg.database.port;
      postgresql-database = cfg.database.name;
      postgresql-username = cfg.database.user;
      postgresql-password = cfg.database.password;

      # OIDC with Authentik per Guacamole docs
      openid-authorization-endpoint = "https://${cfg.authentikDomain}/application/o/authorize/";
      openid-jwks-endpoint = "https://${cfg.authentikDomain}/application/o/${cfg.oidcProviderPath}/jwks/";
      openid-issuer = "https://${cfg.authentikDomain}/application/o/${cfg.oidcProviderPath}/";
      openid-client-id = cfg.clientId;
      openid-redirect-uri = "https://${hostNameEffective}/guacamole/";
      openid-username-claim-type = "preferred_username";
      openid-scope = "openid email profile";
      
      # Additional OIDC options to fix redirect loops
      openid-allowed-redirect-uris = "https://${hostNameEffective}/guacamole/";
      openid-validate-token = "true";
      openid-max-token-length = "8192";
    };

    # Provide required extensions and JDBC driver
    environment.etc."guacamole/extensions/guacamole-auth-sso-openid-${guacVer}.jar".source = "${oidcExtension}/guacamole-auth-sso-openid-${guacVer}.jar";
    environment.etc."guacamole/lib/postgresql-${pgVer}.jar".source = pgDriverSrc;
    environment.etc."guacamole/extensions/guacamole-auth-jdbc-postgresql-${guacVer}.jar".source = "${pgExtension}/guacamole-auth-jdbc-postgresql-${guacVer}.jar";

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
        Environment = [
          "PGPASSWORD=${cfg.database.password}"
        ];
      };
    };

    # Ensure Tomcat starts after network (no local PostgreSQL dependency)
    systemd.services.tomcat = {
      after = [ "network.target" ];
      serviceConfig = {
        ExecStartPre = [
          "${pkgs.coreutils}/bin/mkdir -p /var/lib/guacamole"
          # Import internal CA into a Java truststore so Guacamole trusts Authentik TLS (ignore failures)
          "${pkgs.bash}/bin/bash -lc '${keytool} -importcert -trustcacerts -alias nixmox-internal-ca -file /var/lib/shared-certs/internal-ca.crt -keystore /var/lib/guacamole/java-cacerts -storepass changeit -noprompt || true'"
        ];
      };
    };

    # Point Tomcat/Java at the truststore containing our local CA
    services.tomcat.javaOpts = [
      "-Djavax.net.ssl.trustStore=/var/lib/guacamole/java-cacerts"
      "-Djavax.net.ssl.trustStorePassword=changeit"
    ];

    # Bootstrap a local Guacamole admin user if requested
    systemd.services.guacamole-bootstrap-admin = mkIf cfg.bootstrapAdmin.enable {
      description = "Bootstrap Guacamole local admin user";
      requires = [ "guacamole-pgsql-schema-import.service" ];
      after = [ "guacamole-pgsql-schema-import.service" ];
      wantedBy = [ "tomcat.service" "multi-user.target" ];
      environment = {
        GUAC_BOOTSTRAP_USER = cfg.bootstrapAdmin.username;
        GUAC_BOOTSTRAP_PASS = if cfg.bootstrapAdmin.password == null then "" else cfg.bootstrapAdmin.password;
      };
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "PGPASSWORD=${cfg.database.password}"
        ];
      };
      script = ''
        set -euo pipefail
        if [ -z "''${GUAC_BOOTSTRAP_USER}" ]; then
          echo "[guacamole-bootstrap-admin] Skipping: no username provided" >&2
          exit 0
        fi

        # Generate salt and hash (SHA-256 of salt+password, base64-encoded). If no password provided, generate a random one.
        PASS=''${GUAC_BOOTSTRAP_PASS}
        if [ -z ""$PASS"" ]; then
          PASS=$(${pkgs.openssl}/bin/openssl rand -base64 18)
        fi
        SALT=$(${pkgs.openssl}/bin/openssl rand -base64 32)
        HASH=$(printf "%s" "$SALT$PASS" | ${pkgs.openssl}/bin/openssl dgst -sha256 -binary | ${pkgs.coreutils}/bin/base64)

        # Upsert user
        ${psql} -h ${cfg.database.host} -p ${toString cfg.database.port} -v ON_ERROR_STOP=1 \
          -v username="''${GUAC_BOOTSTRAP_USER}" \
          -v hash="''${HASH}" \
          -v salt="''${SALT}" \
          -U ${cfg.database.user} -d ${cfg.database.name} <<'PSQL'
DO $$
DECLARE
  uid integer;
  v_username text := :'username';
  v_hash text := :'hash';
  v_salt text := :'salt';
BEGIN
  SELECT user_id INTO uid FROM guacamole_user WHERE username = v_username;
  IF uid IS NULL THEN
    INSERT INTO guacamole_user (username, password_hash, password_salt, password_date, disabled)
    VALUES (v_username, v_hash, v_salt, now(), false)
    RETURNING user_id INTO uid;
  ELSE
    UPDATE guacamole_user SET password_hash = v_hash, password_salt = v_salt, password_date = now()
    WHERE user_id = uid;
  END IF;

  -- Grant system admin permission
  IF NOT EXISTS (SELECT 1 FROM guacamole_system_permission WHERE user_id = uid AND permission = 'ADMINISTER') THEN
    INSERT INTO guacamole_system_permission (user_id, permission) VALUES (uid, 'ADMINISTER');
  END IF;
END $$;
PSQL
      '';
    };
  });
}


