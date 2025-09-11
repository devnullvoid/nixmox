{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.prowlarr;
  
  # Get database configuration from manifest
  dbConfig = manifest.services.media.interface.dbs.prowlarr or {};
in {
  options.services.nixmox.media.prowlarr = {
    enable = mkEnableOption "Prowlarr indexer management";

    port = mkOption {
      type = types.int;
      default = 9696;
      description = "Prowlarr web interface port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/prowlarr";
      description = "Prowlarr data directory";
    };
  };

  config = mkIf cfg.enable {
    # Prowlarr configuration
    services.prowlarr = {
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

    # SOPS secrets for Prowlarr databases
    # Temporarily disabled due to timing issue with user creation
    # sops.secrets."media/prowlarr/database_password" = {
    #   sopsFile = ../../../secrets/default.yaml;
    #   owner = "prowlarr";
    #   group = "prowlarr";
    #   mode = "0400";
    # };

    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Prowlarr backend (behind Caddy)
      ];
    };
  };
}