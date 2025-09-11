{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.radarr;
  mediaCfg = config.services.nixmox.media;
  
  # Get database configuration from manifest
  dbConfig = manifest.services.media.interface.dbs.radarr or {};
in {
  options.services.nixmox.media.radarr = {
    enable = mkEnableOption "Radarr movie management";

    port = mkOption {
      type = types.int;
      default = 7878;
      description = "Radarr web interface port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${mediaCfg.dataDir}/radarr";
      description = "Radarr data directory";
    };
  };

  config = mkIf cfg.enable {
    # Radarr configuration
    services.radarr = {
      enable = true;
      dataDir = cfg.dataDir;
      openFirewall = false; # Let Caddy handle external access

      # Use external PostgreSQL if configured
      settings = mkIf (dbConfig != {}) {
        Database = {
          Provider = "PostgreSQL";
          Host = dbConfig.host;
          Port = dbConfig.port;
          Name = dbConfig.name;
          Username = dbConfig.owner;
          Password = "file://${config.sops.secrets."media/radarr/database_password".path}";
        };
      };
    };

    # SOPS secrets for Radarr databases
    sops.secrets."media/radarr/database_password" = {
      sopsFile = ../../../secrets/default.yaml;
      owner = "radarr";
      group = "radarr";
      mode = "0400";
    };





    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Radarr backend (behind Caddy)
      ];
    };
  };
  
  # Export database requirements for filesystem-based discovery
  databaseRequirements = mkIf cfg.enable {
    "radarr-log" = {
      name = "radarr-log";
      owner = "radarr";
      extensions = [];
    };
  };
}
