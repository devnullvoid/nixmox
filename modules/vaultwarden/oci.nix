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

    domain = mkOption {
      type = types.str;
      default = "https://vault.nixmox.lan";
      description = "External URL for Vaultwarden";
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
      default = "auth.nixmox.lan";
      description = "Authentik domain for SSO Authority";
    };
  };

  config = mkIf cfg.enable {
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

    virtualisation.podman.enable = true;
    virtualisation.oci-containers.containers.vaultwarden = {
      image = cfg.image;
      autoStart = true;
      ports = [ "${cfg.bindAddress}:${toString cfg.listenPort}:${toString cfg.listenPort}" ];
      volumes = [
        "${cfg.dataDir}:/data"
        "/etc/ssl/certs/ca-bundle.crt:/etc/ssl/certs/ca-bundle.crt:ro"
      ];
      extraOptions = [
        "--add-host=${cfg.authDomain}:${cfg.lanIp}"
        "--add-host=vault.nixmox.lan:${cfg.lanIp}"
      ];
      environmentFiles = [ "/run/secrets/vaultwarden/env" ];
      environment = {
        DOMAIN = cfg.domain;
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = toString cfg.listenPort;
        WEB_VAULT_ENABLED = "true";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        SSL_CERT_DIR = "/etc/ssl/certs";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
        # SSO static config; client/secret via env file
        SSO_ENABLED = "true";
        SSO_ONLY = "false";
        SSO_DISPLAY_NAME = "Authentik";
        SSO_SCOPES = "openid email profile offline_access";
        # Ensure correct provider slug and trailing slash
        SSO_AUTHORITY = "https://${cfg.authDomain}/application/o/vaultwarden/";
      };
    };
  };
}


