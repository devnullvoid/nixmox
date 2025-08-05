{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.authentik;
in {
  options.services.nixmox.authentik = {
    enable = mkEnableOption "Authentik identity provider";
    
    domain = mkOption {
      type = types.str;
      default = "auth.nixmox.lan";
      description = "Domain for Authentik service";
    };
    
    adminEmail = mkOption {
      type = types.str;
      default = "admin@nixmox.lan";
      description = "Admin email for Authentik";
    };
    
    environmentFile = mkOption {
      type = types.path;
      default = "/run/secrets/authentik/env";
      description = "Path to environment file for Authentik secrets";
    };
  };

  config = mkIf cfg.enable {
    # Create environment file for Authentik
    systemd.services.authentik-env = {
      description = "Create Authentik environment file";
      wantedBy = [ "authentik.service" ];
      before = [ "authentik.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "create-authentik-env" ''
          set -e
          mkdir -p /run/secrets/authentik
          cat > /run/secrets/authentik/env << EOF
          AUTHENTIK_SECRET_KEY=changeme
          AUTHENTIK_POSTGRESQL__PASSWORD=changeme
          AUTHENTIK_REDIS__PASSWORD=changeme
          AUTHENTIK_BOOTSTRAP_PASSWORD=changeme
          AUTHENTIK_EMAIL__PASSWORD=changeme
          EOF
          chmod 600 /run/secrets/authentik/env
        '';
      };
    };

    # PostgreSQL for Authentik
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "authentik" ];
      ensureUsers = [{
        name = "authentik";
        ensureDBOwnership = true;
      }];
    };

    # Redis for Authentik
    services.redis.servers."".enable = true;

    # Authentik service using pre-built package
    systemd.services.authentik = {
      description = "Authentik Identity Provider";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "redis.service" "authentik-env.service" ];
      requires = [ "postgresql.service" "redis.service" "authentik-env.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        ExecStart = "${pkgs.authentik}/bin/ak server";
        EnvironmentFile = cfg.environmentFile;
        Environment = [
          "AUTHENTIK_HOST=${cfg.domain}"
          "AUTHENTIK_LISTEN__HTTP=0.0.0.0:9000"
          "AUTHENTIK_LISTEN__HTTPS=0.0.0.0:9443"
          "AUTHENTIK_BOOTSTRAP__EMAIL=${cfg.adminEmail}"
          "AUTHENTIK_ERROR_REPORTING__ENABLED=false"
          "AUTHENTIK_POSTGRESQL__HOST=127.0.0.1"
          "AUTHENTIK_POSTGRESQL__PORT=5432"
          "AUTHENTIK_POSTGRESQL__USER=authentik"
          "AUTHENTIK_POSTGRESQL__NAME=authentik"
          "AUTHENTIK_REDIS__HOST=127.0.0.1"
          "AUTHENTIK_REDIS__PORT=6379"
        ];
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # Create authentik user
    users.users.authentik = {
      isSystemUser = true;
      group = "authentik";
      home = "/var/lib/authentik";
      createHome = true;
    };

    users.groups.authentik = {};

    # Health check for Authentik
    systemd.services.authentik-health = {
      description = "Authentik health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:9000/health/";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
} 