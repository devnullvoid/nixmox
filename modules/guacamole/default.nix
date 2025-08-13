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

  psql = "${pkgs.postgresql}/bin/psql";
  cat = "${pkgs.coreutils}/bin/cat";
in {
  options.services.nixmox.guacamole = {
    enable = mkEnableOption "Guacamole, a clientless remote desktop gateway";

    hostName = mkOption {
      type = types.str;
      default = "guac.nixmox.lan";
      description = "Public host name for Guacamole";
    };

    authentikDomain = mkOption {
      type = types.str;
      default = "auth.nixmox.lan";
      description = "Authentik domain used for OIDC endpoints";
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
  };

  config = mkIf cfg.enable {
    # Optionally open the Tomcat port (usually proxied locally by Caddy)
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.tomcatPort ];

    # Guacamole services
    services.guacamole-server.enable = true;
    services.guacamole-client.enable = true;

    # Host the client on Tomcat, avoid common 8080 clashes
    services.tomcat.port = cfg.tomcatPort;

    # Guacamole client settings
    services.guacamole-client.settings = {
      guacd-hostname = "localhost";
      guacd-port = config.services.guacamole-server.port;
      extension-priority = "openid";

      # Database config
      postgresql-hostname = "localhost";
      postgresql-database = "guacamole";
      postgresql-username = "guacamole";
      postgresql-password = "";

      # OIDC with Authentik per Guacamole docs
      openid-authorization-endpoint = "https://${cfg.authentikDomain}/application/o/authorize/";
      openid-jwks-endpoint = "https://${cfg.authentikDomain}/application/o/guacamole/jwks/";
      openid-issuer = "https://${cfg.authentikDomain}/application/o/guacamole/";
      openid-client-id = cfg.clientId;
      openid-redirect-uri = "https://${cfg.hostName}/";
      openid-username-claim-type = "preferred_username";
      openid-scope = "openid email profile";
    };

    # Provide required extensions and JDBC driver
    environment.etc."guacamole/extensions/guacamole-auth-sso-openid-${guacVer}.jar".source = "${oidcExtension}/guacamole-auth-sso-openid-${guacVer}.jar";
    environment.etc."guacamole/lib/postgresql-${pgVer}.jar".source = pgDriverSrc;
    environment.etc."guacamole/extensions/guacamole-auth-jdbc-postgresql-${guacVer}.jar".source = "${pgExtension}/guacamole-auth-jdbc-postgresql-${guacVer}.jar";

    # Postgres for Guacamole
    services.postgresql = {
      authentication = ''
        #type database  DBuser  auth-method
        local all       all     trust
        #type database DBuser origin-address auth-method
        host  all       all     127.0.0.1/32   trust
      '';
      enableTCPIP = true;
      ensureDatabases = [ "guacamole" ];
      ensureUsers = [{
        name = "guacamole";
        ensureDBOwnership = true;
      }];
    };

    # Initialize Guacamole DB schema if empty
    systemd.services.guacamole-pgsql-schema-import = {
      enable = true;
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
      wantedBy = [ "tomcat.service" "multi-user.target" ];
      script = ''
        echo "[guacamole-bootstrapper] Info: checking if database 'guacamole' exists but is empty..."
        output=$(${psql} -U guacamole -c "\\dt" 2>&1)
        if [[ "$output" == *"Did not find any relations."* ]]; then
          echo "[guacamole-bootstrapper] Info: installing guacamole postgres database schema..."
          ${cat} ${pgExtension}/schema/*.sql | ${psql} -U guacamole -d guacamole -f -
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
      };
    };

    # Ensure Tomcat starts after Postgres is ready
    systemd.services.tomcat = {
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
    };
  };
}


