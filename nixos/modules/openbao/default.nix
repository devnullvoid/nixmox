{ config, lib, pkgs, manifest, ... }:

with lib;

# OpenBao NixOS Configuration (Manifest-Driven)
#
# This module configures OpenBao (open source fork of HashiCorp Vault) to run as a service.
# All configuration values are now driven by the service manifest.
#
# Database and proxy configuration are automatically constructed from manifest values:
# - Domain: from manifest.services.openbao.interface.proxy.domain
# - Authentik integration: from manifest.services.openbao.interface.auth.oidc.*
# - TLS certificates: from manifest network configuration

let
  cfg = config.services.nixmox.openbao;

  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";

  # Get service configuration from manifest
  serviceConfig = manifest.services.openbao or {};

  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};

  # Get authentication configuration from manifest
  authConfig = serviceConfig.interface.auth or {};

  # Get OIDC configuration from manifest
  oidcConfig = authConfig.oidc or {};

  # Get core services for Authentik configuration
  coreServices = manifest.core_services or {};
  authentikConfig = coreServices.authentik or {};

  # Construct Authentik OIDC issuer URL
  authentikIssuer = "${authentikConfig.hostname or "authentik.nixmox.lan"}/application/o/${oidcConfig.client_id or "openbao-oidc"}/";
in {
  options.services.nixmox.openbao = {
    enable = mkEnableOption "OpenBao secrets management service";

    domain = mkOption {
      type = types.str;
      default = proxyConfig.domain or "bao.nixmox.lan";
      description = "Domain for OpenBao service (from manifest proxy config)";
    };

    primaryDomain = mkOption {
      type = types.str;
      default = baseDomain;
      description = "Primary domain for services (from manifest network config)";
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
          default = "https://${authentikIssuer}";
          description = "OIDC issuer URL (constructed from manifest)";
        };

        clientId = mkOption {
          type = types.str;
          default = oidcConfig.client_id or "openbao-oidc";
          description = "OIDC client ID (from manifest auth config)";
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

    # Use the built-in NixOS OpenBao service
    services.openbao = {
      enable = true;
      
      # Configure OpenBao using the settings option
      settings = {
        # Storage backend
        storage = {
          file = {
            path = "${cfg.openbao.dataDir}/data";
          };
        };
        
        # Listener configuration - HTTP mode without TLS
        listener = {
          tcp = {
            type = "tcp";
            address = "0.0.0.0:${toString cfg.openbao.port}";
            # Explicitly disable TLS to prevent automatic ACME behavior
            tls_disable = true;
          };
        };
        
        # UI settings
        ui = true;
        
        # API settings - using HTTP since TLS is disabled
        api_addr = "http://${cfg.domain}";
        cluster_addr = "http://${config.networking.hostName}.${cfg.primaryDomain}:${toString cfg.openbao.port}";
        
        # Seal configuration (using Shamir seal)
        seal = {
          shamir = {
            secret_shares = 5;
            secret_threshold = 3;
          };
        };
        
        # Telemetry
        telemetry = {
          disable_hostname = true;
          prometheus_retention_time = "30s";
        };
        
        # Explicitly disable automatic TLS/ACME behavior
        disable_cache = false;
      };
    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        cfg.openbao.port  # OpenBao
      ];
    };

    # Create OpenBao user and group (if not handled by the built-in service)
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
