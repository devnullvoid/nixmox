{ config, lib, pkgs, ... }:

with lib;

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
      caCertPath = ../../ca/nixmox-internal-ca.crt;
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

    # Provide Vaultwarden env via SOPS for the container
    sops.secrets."vaultwarden/env" = {
      path = "/run/secrets/vaultwarden/env";
      mode = "0400";
      owner = "root";
      group = "root";
      restartUnits = [ "podman-vaultwarden.service" ];
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
        # Mount the updated CA bundle that includes our internal CA
        "/var/lib/shared-certs/ca-bundle.crt:/etc/ssl/certs/ca-certificates.crt:ro"
      ];
      extraOptions = [
        "--network=host"
        # Ensure name resolution for Authentik and Vaultwarden domains inside the container
        # "--add-host=${cfg.authDomain}:${cfg.lanIp}"
        # "--add-host=${cfg.subdomain}.${config.services.nixmox.domain}:${cfg.lanIp}"
      ];
      environmentFiles = [ "/run/secrets/vaultwarden/env" ];
      environment = {
        DOMAIN = cfg.domain;
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = toString cfg.listenPort;
        WEB_VAULT_ENABLED = "true";
        # Point to the directory containing our internal CA
        SSL_CERT_DIR = "/etc/ssl/certs";
        # SSO static config; client/secret via env file
        SSO_ENABLED = "true";
        SSO_ONLY = "false";
        SSO_DISPLAY_NAME = "Authentik";
        SSO_SCOPES = "openid email profile offline_access";
        # Ensure correct provider slug and trailing slash
        # SSO_AUTHORITY = "https://${cfg.authDomain}/application/o/vaultwarden/";
      };
    };
  };
}


