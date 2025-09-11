{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.jellyfin;
  mediaCfg = config.services.nixmox.media;
in {
  options.services.nixmox.media.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";

    port = mkOption {
      type = types.int;
      default = 8096;
      description = "Jellyfin web interface port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${mediaCfg.dataDir}/jellyfin";
      description = "Jellyfin data directory";
    };

    cacheDir = mkOption {
      type = types.str;
      default = "${mediaCfg.cacheDir}/jellyfin";
      description = "Jellyfin cache directory";
    };

    logDir = mkOption {
      type = types.str;
      default = "${mediaCfg.logDir}/jellyfin";
      description = "Jellyfin log directory";
    };
  };

  config = mkIf cfg.enable {
    # Jellyfin configuration
    services.jellyfin = {
      enable = true;
      user = "jellyfin";
      group = "jellyfin";
      dataDir = cfg.dataDir;
      cacheDir = cfg.cacheDir;
      logDir = cfg.logDir;
      openFirewall = false; # Let Caddy handle external access
    };

    # Create Jellyfin user and group
    users.users.jellyfin = {
      isSystemUser = true;
      group = "jellyfin";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.jellyfin = {};

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 jellyfin jellyfin"
      "d ${cfg.cacheDir} 0755 jellyfin jellyfin"
      "d ${cfg.logDir} 0755 jellyfin jellyfin"
    ];

    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Jellyfin backend (behind Caddy)
      ];
    };

  };
}
