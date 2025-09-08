{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media.prowlarr;
  mediaCfg = config.services.nixmox.media;
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
      default = "${mediaCfg.dataDir}/prowlarr";
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
      settings = mkIf (mediaCfg.databases.prowlarr.type == "postgresql") {
        Database = {
          Provider = "PostgreSQL";
          Host = mediaCfg.databases.prowlarr.host;
          Port = mediaCfg.databases.prowlarr.port;
          Name = mediaCfg.databases.prowlarr.name;
          Username = mediaCfg.databases.prowlarr.user;
          Password = "file://${config.sops.secrets."media/prowlarr/database_password".path}";
        };
      };
    };

    # SOPS secrets for Prowlarr database
    sops.secrets."media/prowlarr/database_password" = {
      sopsFile = ../../../secrets/default.yaml;
      owner = "prowlarr";
      group = "prowlarr";
      mode = "0400";
    };

    # Firewall rules - only allow local access since we're behind Caddy
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port  # Prowlarr backend (behind Caddy)
      ];
    };
  };
}
