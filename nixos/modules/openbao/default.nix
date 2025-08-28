{ config, lib, pkgs, ... }:

with lib;

# OpenBao NixOS Configuration
#
# This module configures OpenBao (open source fork of HashiCorp Vault) to run as a service.
#
# To configure OpenBao:
# 1. Add OpenBao secrets to secrets/default.yaml:
#    openbao:
#      root_token: your_secure_root_token
#      unseal_keys: [key1, key2, key3, key4, key5]
#      oidc_client_secret: your_oidc_client_secret
#
# 2. The module will automatically:
#    - Create OpenBao user and group
#    - Set up systemd service with proper security settings
#    - Configure TLS using internal CA certificates
#    - Set up OIDC authentication with Authentik
#    - Mount secrets via SOPS

let
  cfg = config.services.nixmox.openbao;
in {
  options.services.nixmox.openbao = {
    enable = mkEnableOption "OpenBao secrets management service";

    domain = mkOption {
      type = types.str;
      default = "openbao.nixmox.lan";
      description = "Domain for OpenBao service";
    };

    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for services";
    };

    # OpenBao configuration
    openbao = {
      port = mkOption {
        type = types.int;
        default = 8200;
        description = "OpenBao web interface port";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/openbao";
        description = "OpenBao data directory";
      };

      tls = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable TLS for OpenBao";
        };

        certFile = mkOption {
          type = types.str;
          default = "/etc/ssl/certs/openbao.crt";
          description = "Path to OpenBao TLS certificate";
        };

        keyFile = mkOption {
          type = types.str;
          default = "/etc/ssl/private/openbao.key";
          description = "Path to OpenBao TLS private key";
        };

        caFile = mkOption {
          type = types.str;
          default = "/etc/ssl/certs/ca.crt";
          description = "Path to CA certificate";
        };
      };

      # OIDC configuration
      oidc = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable OIDC authentication";
        };

        issuer = mkOption {
          type = types.str;
          default = "https://auth.nixmox.lan/application/o/openbao-oidc/";
          description = "OIDC issuer URL";
        };

        clientId = mkOption {
          type = types.str;
          default = "openbao-oidc";
          description = "OIDC client ID";
        };

        clientSecret = mkOption {
          type = types.str;
          default = "changeme";
          description = "OIDC client secret (should be overridden via SOPS)";
        };

        redirectUri = mkOption {
          type = types.str;
          default = "https://bao.nixmox.lan/oidc/callback";
          description = "OIDC redirect URI";
        };
      };

      # Security settings
      security = {
        rootToken = mkOption {
          type = types.str;
          default = "changeme";
          description = "OpenBao root token (should be overridden via SOPS)";
        };

        unsealKeys = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "OpenBao unseal keys (should be overridden via SOPS)";
        };
      };

      # Environment variables
      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for OpenBao";
      };
    };
  };

  config = mkIf cfg.enable {
    # SOPS secrets for OpenBao
    sops.secrets = {
      "openbao/root_token" = {
        owner = "openbao";
        group = "openbao";
        mode = "0400";
        restartUnits = [ "openbao.service" ];
      };

      "openbao/unseal_keys" = {
        owner = "openbao";
        group = "openbao";
        mode = "0400";
        restartUnits = [ "openbao.service" ];
      };

      "openbao/oidc_client_secret" = {
        owner = "openbao";
        group = "openbao";
        mode = "0400";
        restartUnits = [ "openbao.service" ];
      };

      "openbao/env" = {
        owner = "openbao";
        group = "openbao";
        mode = "0400";
        path = "/run/secrets/openbao/env";
        restartUnits = [ "openbao.service" ];
      };
    };

    # OpenBao service
    services.openbao = {
      enable = true;

      # Basic settings
      address = "0.0.0.0:${toString cfg.openbao.port}";
      dataDir = cfg.openbao.dataDir;

      # TLS configuration
      tlsCertFile = cfg.openbao.tls.certFile;
      tlsKeyFile = cfg.openbao.tls.keyFile;
      tlsCaFile = cfg.openbao.tls.caFile;

      # Storage backend (file storage for simplicity)
      storage = {
        file = {
          path = "${cfg.openbao.dataDir}/data";
        };
      };

      # Listener configuration
      listener.tcp = {
        address = "0.0.0.0:${toString cfg.openbao.port}";
        tls_cert_file = cfg.openbao.tls.certFile;
        tls_key_file = cfg.openbao.tls.keyFile;
        tls_ca_file = cfg.openbao.tls.caFile;
      };

      # UI settings
      ui = true;

      # API settings
      api_addr = "https://bao.${cfg.primaryDomain}";
      cluster_addr = "https://${config.networking.hostName}.${cfg.primaryDomain}:${toString cfg.openbao.port}";

      # Seal configuration (using Shamir seal)
      seal = {
        shamir = {
          secret_shares = 5;
          secret_threshold = 3;
        };
      };

      # Telemetry (basic)
      telemetry = {
        disable_hostname = true;
        prometheus_retention_time = "30s";
      };

      # Additional environment variables
      extraEnvironmentVars = cfg.openbao.environment // {
        # OIDC Configuration
        OPENBAO_OIDC_ISSUER = cfg.openbao.oidc.issuer;
        OPENBAO_OIDC_CLIENT_ID = cfg.openbao.oidc.clientId;
        OPENBAO_OIDC_REDIRECT_URI = cfg.openbao.oidc.redirectUri;

        # UI settings
        OPENBAO_UI = "true";
        OPENBAO_DISABLE_MLOCK = "true";

        # Clustering (disabled for single node)
        OPENBAO_CLUSTER_ADDR = "https://${config.networking.hostName}.${cfg.primaryDomain}:${toString cfg.openbao.port}";
        OPENBAO_API_ADDR = "https://bao.${cfg.primaryDomain}";
      };
    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        cfg.openbao.port  # OpenBao
      ];
    };

    # Create OpenBao user
    users.users.openbao = {
      isSystemUser = true;
      group = "openbao";
      home = cfg.openbao.dataDir;
      createHome = true;
    };

    users.groups.openbao = {};

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.openbao.dataDir} 0755 openbao openbao"
      "d ${cfg.openbao.dataDir}/data 0755 openbao openbao"
      "d ${cfg.openbao.dataDir}/logs 0755 openbao openbao"
    ];

    # Systemd services
    systemd.services = {
      # OpenBao service
      "openbao" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStartPre = [
            "${pkgs.coreutils}/bin/mkdir -p ${cfg.openbao.dataDir}/data"
            "${pkgs.coreutils}/bin/mkdir -p ${cfg.openbao.dataDir}/logs"
          ];

          # User and group
          User = "openbao";
          Group = "openbao";

          # Working directory
          WorkingDirectory = cfg.openbao.dataDir;

          # Sensitive environment via SOPS
          EnvironmentFile = config.sops.secrets."openbao/env".path;

          # Environment
          Environment = lib.mapAttrsToList (name: value: "${name}=${toString value}") config.services.openbao.extraEnvironmentVars;

          # Security settings
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;

          # Capabilities
          AmbientCapabilities = "CAP_NET_BIND_SERVICE";
          CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";

          # Logging
          StandardOutput = "journal";
          StandardError = "journal";

          # Restart policy
          Restart = "always";
          RestartSec = "10s";
        };
      };
    };

    # Health check for OpenBao
    systemd.services.openbao-health = {
      description = "OpenBao health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "openbao.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in {1..20}; do ${pkgs.curl}/bin/curl -f -k https://localhost:${toString cfg.openbao.port}/v1/sys/health && exit 0; sleep 2; done; exit 1'";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };

    # Default environment variables
    services.nixmox.openbao.openbao.environment = {
      # Security settings
      OPENBAO_LOG_LEVEL = "info";
      OPENBAO_LOG_FORMAT = "json";

      # Performance settings
      OPENBAO_MAX_LEASE_TTL = "768h";
      OPENBAO_DEFAULT_LEASE_TTL = "768h";

      # Disable mlock for containerized environments
      OPENBAO_DISABLE_MLOCK = "true";

      # Rate limiting
      OPENBAO_RATE_LIMIT_AUDIT_LOG = "false";
      OPENBAO_RATE_LIMIT_REQUEST_COUNT = "0";
      OPENBAO_RATE_LIMIT_PERIOD = "1s";

      # Telemetry
      OPENBAO_TELEMETRY_DISABLE_HOSTNAME = "true";
      OPENBAO_TELEMETRY_PROMETHEUS_RETENTION_TIME = "30s";

      # Additional security headers
      OPENBAO_DISABLE_CACHE = "false";
      OPENBAO_CACHE_SIZE = "16384";
    };
  };
}
