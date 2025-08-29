{ config, lib, pkgs, ... }:

with lib;

# Vaultwarden OCI Container with PostgreSQL and Authentik SSO Support
#
# This module configures Vaultwarden as an OCI container with full PostgreSQL
# and Authentik SSO integration.
#
# All sensitive configuration comes from SOPS secrets:
# - DATABASE_URL: PostgreSQL connection string
# - OIDC_ISSUER: Authentik OIDC provider URL
# - OIDC_REDIRECT_URI: Vaultwarden OIDC callback URL
# - SSO_AUTHORITY: Authentik SSO authority URL
# - SSO_CLIENT_ID/SECRET: OIDC client credentials
# - ADMIN_TOKEN: Vaultwarden admin token
# - JWT_SECRET: JWT signing secret
#
# SOPS env file (vaultwarden/env) should contain:
# DATABASE_URL=postgresql://vaultwarden:password@192.168.99.11:5432/vaultwarden
# OIDC_ISSUER=https://auth.nixmox.lan/application/o/vaultwarden-oidc/
# OIDC_REDIRECT_URI=https://vault.nixmox.lan/oidc/callback
# SSO_AUTHORITY=https://auth.nixmox.lan/application/o/vaultwarden-oidc/
# SSO_CLIENT_ID=vaultwarden-oidc
# SSO_CLIENT_SECRET=your_client_secret
# ADMIN_TOKEN=your_admin_token
# JWT_SECRET=your_jwt_secret

let
  cfg = config.services.nixmox.vaultwarden.oci;
in {
  imports = [ ../shared/internal-ca.nix ];
  options.services.nixmox.vaultwarden.oci = {
    enable = mkEnableOption "Run Vaultwarden as an OCI container (Timshel SSO-capable build)";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/timshel/vaultwarden:latest";
      description = "Container image for Vaultwarden";
    };

    listenPort = mkOption {
      type = types.int;
      default = 8080;
      description = "Port Vaultwarden listens on inside the container";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind the Vaultwarden port to";
    };

    subdomain = mkOption {
      type = types.str;
      default = "vault";
      description = "Subdomain for Vaultwarden; full host becomes <subdomain>.<services.nixmox.domain>";
    };

    domain = mkOption {
      type = types.str;
      default = "";
      description = "External URL for Vaultwarden; if empty, constructed from subdomain + base domain with https://";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/vaultwarden";
      description = "Data directory on host mounted to /data";
    };
    


    # lanIp = mkOption {
    #   type = types.str;
    #   default = "192.168.99.10";
    #   description = "LAN IP for add-host mappings for auth/vault domains";
    # };

    # authDomain = mkOption {
    #   type = types.str;
    #   default = "auth.nixmox.lan";
    #   description = "Authentik domain for SSO Authority";
    # };
  };

  config = mkIf cfg.enable {
    # Enable internal CA certificate distribution
    services.nixmox.internalCa = {
      enable = true;
    };
    
    # Ensure local firewall permits backend traffic on the Vaultwarden port
    networking.firewall.allowedTCPPorts = [ cfg.listenPort ];
    # Construct DOMAIN by default from base domain
    services.nixmox.vaultwarden.oci.domain = mkDefault ("https://" + cfg.subdomain + "." + config.services.nixmox.domain);
    # Ensure native service is off when using container
    services.nixmox.vaultwarden.enable = lib.mkForce false;

    # Ensure local resolution works even before DNS is in place
    networking.hosts."127.0.0.1" = [ "${cfg.subdomain}.${config.services.nixmox.domain}" ];
    # Ensure auth domain resolution works for OIDC discovery
    # networking.hosts."${cfg.lanIp}" = [ cfg.authDomain ];

    # Podman bridged networking needs nftables (netavark) for port publishing
    networking.nftables.enable = true;

    # Create Vaultwarden data directory
    systemd.services.vaultwarden-data-dir = {
      description = "Create Vaultwarden data directory";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman-vaultwarden.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${cfg.dataDir}";
        ExecStartPost = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/chown 1000:1000 ${cfg.dataDir} && ${pkgs.coreutils}/bin/chmod 755 ${cfg.dataDir}'";
      };
    };

    # SOPS secrets for Vaultwarden container
    sops.secrets = {
      "vaultwarden/env" = {
        path = "/run/secrets/vaultwarden/env";
        mode = "0400";
        owner = "root";
        group = "root";
        restartUnits = [ "podman-vaultwarden.service" ];
      };
    };

    # CA certificate is now handled by the shared internal-ca module

    virtualisation.oci-containers.containers.vaultwarden = {
      image = cfg.image;
      autoStart = true;
      # Use host networking to avoid LXC NAT/loopback quirks
      ports = [ ];
      volumes = [
        "${cfg.dataDir}:/data"
        # Mount the shared internal CA certificate
        "/var/lib/shared-certs/internal-ca.crt:/etc/ssl/certs/internal-ca.crt:ro"
        # Mount the CA bundle that includes both system CAs and internal CA
        "/var/lib/shared-certs/ca-bundle.crt:/etc/ssl/certs/ca-certificates.crt:ro"
      ];
      extraOptions = [
        "--network=host"
      ];
      environmentFiles = [ config.sops.secrets."vaultwarden/env".path ];
      environment = {
        DOMAIN = cfg.domain;
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = toString cfg.listenPort;
        WEB_VAULT_ENABLED = "true";

        # PostgreSQL Database Configuration comes from SOPS env file
        DATABASE_MAX_CONNS = "10";
        DATABASE_TIMEOUT = "30";
        DATABASE_CONNECTION_RETRIES = "3";
        DATABASE_POOL_SIZE = "10";

        # SSL Configuration - point to the CA bundle that includes both system CAs and internal CA
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";

        # SSO Configuration - using correct values from Authentik
        SSO_ENABLED = "true";
        SSO_ONLY = "false";
        SSO_DISPLAY_NAME = "Authentik";
        SSO_SCOPES = "openid email profile offline_access";
      };
    };
  };
}


