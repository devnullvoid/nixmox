{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.internalCa;
in {
  options.services.nixmox.internalCa = {
    enable = mkEnableOption "Internal CA certificate distribution";
    
    enableWildcardKey = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to install the wildcard private key (only needed for hosts serving HTTPS)";
    };
    
    caName = mkOption {
      type = types.str;
      default = "NixMox Internal CA";
      description = "Name for the internal CA";
    };
  };

  config = mkIf cfg.enable {
    # Add our internal CA certificate to the system trust store
    # This is the proper NixOS-native way to handle CA certificates
    security.pki.certificates = [
      (builtins.readFile ../../../certs/nixmox-internal-ca.crt)
    ];
    
    # Copy wildcard certificate (not sensitive, so not in SOPS)
    environment.etc."var/lib/shared-certs/wildcard-nixmox-lan.crt" = mkIf cfg.enableWildcardKey {
      source = ../../../certs/wildcard-nixmox-lan.crt;
      mode = "0644";
    };

    # SOPS secrets for wildcard private key (only when explicitly enabled)
    sops.secrets."internal_ca/wildcard_private_key" = mkIf cfg.enableWildcardKey {
      sopsFile = ../../../secrets/default.yaml;
      path = "/var/lib/shared-certs/wildcard-nixmox-lan.key";
      mode = "0644";
      owner = "root";
      group = "root";
    };
    
    # Create shared certificate directory for wildcard certificates
    systemd.tmpfiles.rules = [
      "d /var/lib/shared-certs 0755 root root -"
    ];
  };
}
