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
    
    # Copy certificates to shared directory
    system.activationScripts.setupSharedCerts = ''
      # Ensure directory exists
      mkdir -p /var/lib/shared-certs
      chmod 755 /var/lib/shared-certs
      
      # Copy wildcard certificate if it exists
      if [ -f ../../../certs/wildcard-nixmox-lan.crt ]; then
        cp ../../../certs/wildcard-nixmox-lan.crt /var/lib/shared-certs/wildcard-nixmox-lan.crt
        chmod 644 /var/lib/shared-certs/wildcard-nixmox-lan.crt
      fi
      
      # Copy internal CA certificate to system CA directory if it exists
      if [ -f /var/lib/shared-certs/internal-ca.crt ] && [ -s /var/lib/shared-certs/internal-ca.crt ]; then
        echo "Installing internal CA certificate to system CA directory..."
        mkdir -p /etc/ssl/certs
        cp /var/lib/shared-certs/internal-ca.crt /etc/ssl/certs/
        chmod 644 /etc/ssl/certs/internal-ca.crt
        echo "Internal CA certificate installed successfully"
        
        # Create a proper CA bundle for containers that includes both system CAs and our internal CA
        echo "Creating CA bundle for containers..."
        # Always create from individual PEM files to avoid corruption
        echo "Creating CA bundle from individual PEM files..."
        find /etc/ssl/certs -name "*.pem" -exec cat {} \; > /var/lib/shared-certs/ca-bundle.crt
        echo "" >> /var/lib/shared-certs/ca-bundle.crt
        cat /var/lib/shared-certs/internal-ca.crt >> /var/lib/shared-certs/ca-bundle.crt
        echo "CA bundle created from individual PEM files + internal CA"
      else
        echo "Internal CA certificate not yet available (will be available after SOPS decryption)"
      fi
    '';
  };
}
