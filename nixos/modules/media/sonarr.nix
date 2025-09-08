{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.sonarr;
  mediaCfg = config.services.nixmox.media;
in {
  options.services.nixmox.media.sonarr = {
    enable = mkEnableOption "Sonarr TV show management";

    port = mkOption {
      type = types.int;
      default = 8989;
      description = "Sonarr web interface port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${mediaCfg.dataDir}/sonarr";
      description = "Sonarr data directory";
    };
  };

  config = mkIf cfg.enable {
    # Sonarr configuration
    services.sonarr = {
      enable = true;
      dataDir = cfg.dataDir;
      openFirewall = false; # Let Caddy handle external access

      # Use external PostgreSQL if configured
      settings = mkIf (mediaCfg.databases.sonarr.type == "postgresql") {
        Database = {
          Provider = "PostgreSQL";
          Host = mediaCfg.databases.sonarr.host;
          Port = mediaCfg.databases.sonarr.port;
          Name = mediaCfg.databases.sonarr.name;
          Username = mediaCfg.databases.sonarr.user;
          Password = "file://${config.sops.secrets."media/sonarr/database_password".path}";
        };
      };
    };

    # SOPS secrets for Sonarr database
    sops.secrets."media/sonarr/database_password" = {
      sopsFile = ../../../secrets/default.yaml;
      owner = "sonarr";
      group = "sonarr";
      mode = "0400";
    };

    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Sonarr backend (behind Caddy)
      ];
    };
  };
}
