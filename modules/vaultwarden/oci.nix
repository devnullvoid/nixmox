{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.vaultwarden.oci;
in {
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

    lanIp = mkOption {
      type = types.str;
      default = "192.168.88.194";
      description = "LAN IP for add-host mappings for auth/vault domains";
    };

    authDomain = mkOption {
      type = types.str;
      default = config.services.nixmox.authentik.domain;
      description = "Authentik domain for SSO Authority";
    };
  };

  config = mkIf cfg.enable {
    # Construct DOMAIN by default from base domain
    services.nixmox.vaultwarden.oci.domain = mkDefault ("https://" + cfg.subdomain + "." + config.services.nixmox.domain);
    # Ensure native service is off when using container
    services.nixmox.vaultwarden.enable = lib.mkForce false;

    # Provide Vaultwarden env via SOPS for the container
    sops.secrets."vaultwarden/env" = {
      path = "/run/secrets/vaultwarden/env";
      mode = "0400";
      owner = "root";
      group = "root";
      restartUnits = [ "podman-vaultwarden.service" ];
    };

    virtualisation.oci-containers.containers.vaultwarden = {
      image = cfg.image;
      autoStart = true;
      ports = [ "${cfg.bindAddress}:${toString cfg.listenPort}:${toString cfg.listenPort}" ];
      volumes = [
        "${cfg.dataDir}:/data"
        # Ensure container trusts host CA bundle (incl. local CA) at Debian's default path
        "/etc/ssl/certs/ca-bundle.crt:/etc/ssl/certs/ca-certificates.crt:ro"
      ];
      extraOptions = [
        # Ensure name resolution for Authentik and Vaultwarden domains inside the container
        "--add-host=${cfg.authDomain}:${cfg.lanIp}"
        "--add-host=${cfg.subdomain}.${config.services.nixmox.domain}:${cfg.lanIp}"
      ];
      environmentFiles = [ "/run/secrets/vaultwarden/env" ];
      environment = {
        DOMAIN = cfg.domain;
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = toString cfg.listenPort;
        WEB_VAULT_ENABLED = "true";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        SSL_CERT_DIR = "/etc/ssl/certs";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
        # SSO static config; client/secret via env file
        SSO_ENABLED = "true";
        SSO_ONLY = "false";
        SSO_DISPLAY_NAME = "Authentik";
        SSO_SCOPES = "openid email profile offline_access";
        # Ensure correct provider slug and trailing slash
        SSO_AUTHORITY = "https://${cfg.authDomain}/application/o/vaultwarden/";
      };
    };

    # Expose Caddy vhost for Vaultwarden
    services.nixmox.caddy.services.vaultwarden = {
      domain = builtins.replaceStrings ["https://"] [""] cfg.domain;
      backend = cfg.bindAddress;
      port = cfg.listenPort;
      enableAuth = false;
    };
  };
}


