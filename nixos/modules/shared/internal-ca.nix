{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.internalCa;
in {
  options.services.nixmox.internalCa = {
    enable = mkEnableOption "Internal CA certificate distribution";
    
    caCertPath = mkOption {
      type = types.path;
      description = "Path to the internal CA certificate file";
    };
    
    wildcardCertPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the wildcard certificate file";
    };
    
    wildcardKeyPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the wildcard private key file";
    };
    
    caName = mkOption {
      type = types.str;
      default = "NixMox Internal CA";
      description = "Name for the internal CA";
    };
  };

  config = mkIf cfg.enable {
    # Add CA to system trust store
    security.pki.certificates = [ (builtins.readFile cfg.caCertPath) ];
    
    # Create shared certificate directory
    systemd.tmpfiles.rules = [
      "d /var/lib/shared-certs 0755 root root"
      "f /var/lib/shared-certs/internal-ca.crt 0644 root root"
      "f /var/lib/shared-certs/wildcard-nixmox-lan.crt 0644 root root"
    ];
    
    # SOPS secrets for wildcard private key
    sops.secrets."internal_ca/wildcard_private_key" = {
      sopsFile = ../../../secrets/default.yaml;
      path = "/var/lib/shared-certs/wildcard-nixmox-lan.key";
      mode = "0600";
      owner = "root";
      group = "root";
    };
    
    # Copy CA certificate on activation
    system.activationScripts.copyInternalCa = ''
      echo "Installing internal CA certificate..."
      # Ensure directory exists
      mkdir -p /var/lib/shared-certs
      chmod 755 /var/lib/shared-certs
      
      cp ${cfg.caCertPath} /var/lib/shared-certs/internal-ca.crt
      
      # Copy wildcard certificate if provided
      ${lib.optionalString (cfg.wildcardCertPath != null) ''
        echo "Installing wildcard certificate..."
        cp ${cfg.wildcardCertPath} /var/lib/shared-certs/wildcard-nixmox-lan.crt
      ''}
      
      # Create a CA bundle that includes our internal CA for containers
      echo "Creating CA bundle for containers..."
      cat /etc/ssl/certs/ca-certificates.crt /var/lib/shared-certs/internal-ca.crt > /var/lib/shared-certs/ca-bundle.crt
      
      echo "Internal CA and wildcard certificates installed successfully"
    '';
    
    # Ensure the shared-certs directory exists
    systemd.services.setup-shared-certs = {
      description = "Setup shared certificates directory";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman.service" "docker.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${pkgs.coreutils}/bin/mkdir -p /var/lib/shared-certs"
          "${pkgs.coreutils}/bin/chmod 755 /var/lib/shared-certs"
        ];
        RemainAfterExit = true;
      };
    };
  };
}
