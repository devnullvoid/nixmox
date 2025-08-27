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
    # SOPS secrets for CA certificate
    sops.secrets."internal_ca/certificate" = {
      sopsFile = ../../../secrets/default.yaml;
      path = "/var/lib/shared-certs/internal-ca.crt";
      mode = "0644";
      owner = "root";
      group = "root";
    };
    
    # SOPS secrets for wildcard private key (only when explicitly enabled)
    sops.secrets."internal_ca/wildcard_private_key" = mkIf cfg.enableWildcardKey {
      sopsFile = ../../../secrets/default.yaml;
      path = "/var/lib/shared-certs/wildcard-nixmox-lan.key";
      mode = "0644";
      owner = "root";
      group = "root";
    };
    
    # Create shared certificate directory
    systemd.tmpfiles.rules = [
      "d /var/lib/shared-certs 0755 root root -"
    ];
    
    # Create symlinks for certificates
    system.activationScripts.setupSharedCerts = ''
      # Create symlink for wildcard certificate (copy from existing file)
      if [ -f ../../../certs/wildcard-nixmox-lan.crt ]; then
        cp ../../../certs/wildcard-nixmox-lan.crt /var/lib/shared-certs/wildcard-nixmox-lan.crt
        chmod 644 /var/lib/shared-certs/wildcard-nixmox-lan.crt
      fi
      
      # Create CA bundle for containers
      if [ -f /var/lib/shared-certs/internal-ca.crt ]; then
        cat /var/lib/shared-certs/internal-ca.crt > /var/lib/shared-certs/ca-bundle.crt
      fi
    '';
    
    # Copy CA certificate on activation
    system.activationScripts.copyInternalCa = ''
      echo "Installing internal CA certificate..."
      # Ensure directory exists
      mkdir -p /var/lib/shared-certs
      chmod 755 /var/lib/shared-certs
      
      # Create a CA bundle that includes our internal CA for containers
      echo "Creating CA bundle for containers..."
      cat /etc/ssl/certs/ca-certificates.crt /var/lib/shared-certs/internal-ca.crt > /var/lib/shared-certs/ca-bundle.crt
      
      echo "Internal CA certificate installed successfully"
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
