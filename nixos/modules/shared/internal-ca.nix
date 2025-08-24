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
    ];
    
    # Copy CA certificate on activation
    system.activationScripts.copyInternalCa = ''
      echo "Installing internal CA certificate..."
      cp ${cfg.caCertPath} /var/lib/shared-certs/internal-ca.crt
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
          "mkdir -p /var/lib/shared-certs"
          "chmod 755 /var/lib/shared-certs"
        ];
        RemainAfterExit = true;
      };
    };
  };
}
