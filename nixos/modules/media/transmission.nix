{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.transmission;
  mediaCfg = config.services.nixmox.media;
in {
  options.services.nixmox.media.transmission = {
    enable = mkEnableOption "Transmission torrent client";

    port = mkOption {
      type = types.int;
      default = 9091;
      description = "Transmission web interface port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${mediaCfg.dataDir}/transmission";
      description = "Transmission data directory";
    };

    downloadDir = mkOption {
      type = types.str;
      default = mediaCfg.torrentsDir;
      description = "Transmission download directory";
    };
  };

  config = mkIf cfg.enable {
    # Transmission configuration
    services.transmission = {
      enable = true;
      user = "transmission";
      group = "transmission";
      home = cfg.dataDir;
      settings = {
        # Basic settings
        rpc-enabled = true;
        rpc-bind-address = "0.0.0.0";
        rpc-port = cfg.port;
        rpc-whitelist-enabled = false; # Disable whitelist for Caddy access
        
        # Download settings
        download-dir = cfg.downloadDir;
        incomplete-dir = "${cfg.downloadDir}/incomplete";
        incomplete-dir-enabled = true;
        
        # Network settings
        peer-port = 51413;
        peer-port-random-enabled = false;
        
        # Security settings
        rpc-authentication-required = true;
        rpc-username = "transmission";
        rpc-password-file = config.sops.secrets."media/transmission_password".path;
        
        # Performance settings
        cache-size-mb = 4;
        prefetch-enabled = true;
        
        # Logging
        log-level = "info";
        logfile-enabled = true;
        logfile = "${mediaCfg.logDir}/transmission.log";
      };
    };

    # Create Transmission user and group
    users.users.transmission = {
      isSystemUser = true;
      group = "transmission";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.transmission = {};

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 transmission transmission"
      "d ${cfg.downloadDir} 0755 transmission transmission"
      "d ${cfg.downloadDir}/incomplete 0755 transmission transmission"
      "d ${mediaCfg.logDir} 0755 transmission transmission"
    ];

    # SOPS secrets for Transmission
    sops.secrets."media/transmission_password" = {
      sopsFile = ../../../secrets/default.yaml;
      owner = "transmission";
      group = "transmission";
      mode = "0400";
    };

    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Transmission web interface (behind Caddy)
        51413     # Transmission peer port
      ];
    };
  };
}
