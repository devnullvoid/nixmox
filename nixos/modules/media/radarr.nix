{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.radarr;
  
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
      default = "/var/lib/radarr";
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
      settings = {
        # Authentication settings (always applied)
        Auth = {
          Enabled = true;
          Method = "basic";
          Required = true;
        };
      } // mkIf (dbConfig != {}) {
        Postgres = {
          Host = dbConfig.host;
          Port = dbConfig.port;
          User = dbConfig.owner;
          Password = "admin123";
          MainDb = dbConfig.name;
          LogDb = "${dbConfig.name}-log";
        };
      };
    };

    # SOPS secrets for Radarr databases
    # Temporarily disabled due to timing issue with user creation
    # sops.secrets."media/radarr/database_password" = {
    #   sopsFile = ../../../secrets/default.yaml;
    #   owner = "radarr";
    #   group = "radarr";
    #   mode = "0400";
    # };

    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Radarr backend (behind Caddy)
      ];
    };
  };
}