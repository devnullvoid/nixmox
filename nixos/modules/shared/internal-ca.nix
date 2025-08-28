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
    
    # SOPS secrets for wildcard certificate (only when explicitly enabled)
    sops.secrets."internal_ca/wildcard_cert" = mkIf cfg.enableWildcardKey {
      sopsFile = ../../../secrets/default.yaml;
      path = "/var/lib/shared-certs/wildcard-nixmox-lan.crt";
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
    
    # Set environment variables to use our custom CA bundle
    environment.variables = {
      SSL_CERT_FILE = "/var/lib/shared-certs/ca-bundle.crt";
      CURL_CA_BUNDLE = "/var/lib/shared-certs/ca-bundle.crt";
    };

    # Copy certificates to shared directory
    system.activationScripts.setupSharedCerts = ''
      # Ensure directory exists
      mkdir -p /var/lib/shared-certs
      chmod 755 /var/lib/shared-certs

      # Create a proper CA bundle for containers that includes both system CAs and our internal CA
      if [ -f /var/lib/shared-certs/internal-ca.crt ] && [ -s /var/lib/shared-certs/internal-ca.crt ]; then
        echo "Creating CA bundle for containers..."
        # Copy system CA bundle and append our internal CA
        if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
          cp /etc/ssl/certs/ca-certificates.crt /var/lib/shared-certs/ca-bundle.crt
          echo "" >> /var/lib/shared-certs/ca-bundle.crt
        fi
        cat /var/lib/shared-certs/internal-ca.crt >> /var/lib/shared-certs/ca-bundle.crt
        echo "CA bundle created with internal CA appended"
      else
        echo "Internal CA certificate not yet available (will be available after SOPS decryption)"
      fi
    '';
  };
}
