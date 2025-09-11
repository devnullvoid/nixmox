{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.sonarr;
  mediaCfg = config.services.nixmox.media;
  
  # Get database configuration from manifest
  dbConfig = manifest.services.media.interface.dbs.sonarr or {};
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
      settings = mkIf (dbConfig != {}) {
        Database = {
          Provider = "PostgreSQL";
          Host = dbConfig.host;
          Port = dbConfig.port;
          Name = dbConfig.name;
          Username = dbConfig.owner;
          Password = "file://${config.sops.secrets."media/sonarr/database_password".path}";
        };
      };
    };

    # SOPS secrets for Sonarr databases
    sops.secrets."media/sonarr/database_password" = {
      sopsFile = ../../../secrets/default.yaml;
      owner = "sonarr";
      group = "sonarr";
      mode = "0400";
    };

    # Declare additional database requirements for Sonarr (same pattern as Caddy)
    services.nixmox.postgresqlServiceConfigs.sonarr = {
      additionalDatabases = {
        log = {
          name = "sonarr-log";
          owner = "sonarr";
          extensions = [];
        };
      };
    };
  };
  
  # Export database requirements for filesystem-based discovery
  databaseRequirements = mkIf cfg.enable {
    "sonarr-log" = {
      name = "sonarr-log";
      owner = "sonarr";
      extensions = [];
    };
  };





    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Sonarr backend (behind Caddy)
      ];
    };
  };
}
