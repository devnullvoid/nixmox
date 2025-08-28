{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media;

  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";

  # Get service configuration from manifest
  serviceConfig = manifest.services.media or {};

  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};

  # Get authentication configuration from manifest
  authConfig = serviceConfig.interface.auth or {};
in {
  options.services.nixmox.media = {
    enable = mkEnableOption "Media server stack";

    subdomain = mkOption {
      type = types.str;
      default = "media";
      description = "Subdomain for media services; full host becomes <subdomain>.<services.nixmox.domain>";
    };

    hostName = mkOption {
      type = types.str;
      default = proxyConfig.domain or "${cfg.subdomain}.${baseDomain}";
      description = "Public host name for media services (from manifest proxy config)";
    };

    # Jellyfin configuration
    jellyfin = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Jellyfin media server";
      };

      port = mkOption {
        type = types.int;
        default = 8096;
        description = "Jellyfin web interface port";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/jellyfin";
        description = "Jellyfin data directory";
      };

      cacheDir = mkOption {
        type = types.str;
        default = "/var/cache/jellyfin";
        description = "Jellyfin cache directory";
      };

      logDir = mkOption {
        type = types.str;
        default = "/var/log/jellyfin";
        description = "Jellyfin log directory";
      };
    };

    # Sonarr configuration
    sonarr = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Sonarr TV show manager";
      };

      port = mkOption {
        type = types.int;
        default = 8989;
        description = "Sonarr web interface port";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/sonarr";
        description = "Sonarr data directory";
      };
    };

    # Radarr configuration
    radarr = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Radarr movie manager";
      };

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

    # Prowlarr configuration
    prowlarr = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Prowlarr indexer manager";
      };

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

    # Media directories
    mediaDirs = {
      movies = mkOption {
        type = types.str;
        default = "/var/lib/media/movies";
        description = "Movies directory";
      };

      tv = mkOption {
        type = types.str;
        default = "/var/lib/media/tv";
        description = "TV shows directory";
      };

      music = mkOption {
        type = types.str;
        default = "/var/lib/media/music";
        description = "Music directory";
      };

      downloads = mkOption {
        type = types.str;
        default = "/var/lib/media/downloads";
        description = "Downloads directory";
      };

      torrents = mkOption {
        type = types.str;
        default = "/var/lib/media/torrents";
        description = "Torrents directory";
      };
    };

    # Database configuration
    database = {
      type = mkOption {
        type = types.enum [ "postgresql" "sqlite" ];
        default = "postgresql";
        description = "Database type to use";
      };

      host = mkOption {
        type = types.str;
        default = "postgresql.nixmox.lan";
        description = "Database host";
      };

      port = mkOption {
        type = types.int;
        default = 5432;
        description = "Database port";
      };

      name = mkOption {
        type = types.str;
        default = "media";
        description = "Base database name";
      };

      user = mkOption {
        type = types.str;
        default = "media";
        description = "Database user";
      };

      password = mkOption {
        type = types.str;
        default = "changeme";
        description = "Database password (should be overridden via SOPS)";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${config.services.nixmox.domain}";
    in {
      # Ensure local resolution works even before DNS is in place
      networking.hosts = {
        "127.0.0.1" = [ hostNameEffective ];
      } // mkIf (cfg.database.host != "localhost") {
        "${cfg.database.host}" = [ "postgresql.nixmox.lan" ];
      };

      # Jellyfin configuration
      services.jellyfin = mkIf cfg.jellyfin.enable {
        enable = true;
        user = "jellyfin";
        group = "jellyfin";
        dataDir = cfg.jellyfin.dataDir;
        cacheDir = cfg.jellyfin.cacheDir;
        logDir = cfg.jellyfin.logDir;
        openFirewall = false; # Let Caddy handle external access
      };

      # Sonarr configuration
      services.sonarr = mkIf cfg.sonarr.enable {
        enable = true;
        dataDir = cfg.sonarr.dataDir;
        openFirewall = false; # Let Caddy handle external access

        # Use external PostgreSQL if configured
        settings = mkIf (cfg.database.type == "postgresql") {
          "Database:Provider" = "PostgreSQL";
          "Database:ConnectionString" = "Host=${cfg.database.host};Port=${toString cfg.database.port};Database=${cfg.database.name};Username=${cfg.database.user};Password=${cfg.database.password}";
        };
      };

      # Radarr configuration
      services.radarr = mkIf cfg.radarr.enable {
        enable = true;
        dataDir = cfg.radarr.dataDir;
        openFirewall = false; # Let Caddy handle external access

        # Use external PostgreSQL if configured
        settings = mkIf (cfg.database.type == "postgresql") {
          "Database:Provider" = "PostgreSQL";
          "Database:ConnectionString" = "Host=${cfg.database.host};Port=${toString cfg.database.port};Database=${cfg.database.name};Username=${cfg.database.user};Password=${cfg.database.password}";
        };
      };

      # Prowlarr configuration
      services.prowlarr = mkIf cfg.prowlarr.enable {
        enable = true;
        dataDir = cfg.prowlarr.dataDir;
        openFirewall = false; # Let Caddy handle external access

        # Use external PostgreSQL if configured
        settings = mkIf (cfg.database.type == "postgresql") {
          "Database:Provider" = "PostgreSQL";
          "Database:ConnectionString" = "Host=${cfg.database.host};Port=${toString cfg.database.port};Database=${cfg.database.name};Username=${cfg.database.user};Password=${cfg.database.password}";
        };
      };

      # Transmission for downloads
      services.transmission = {
        enable = true;

        # Settings
        settings = {
          # Basic settings
          download-dir = cfg.mediaDirs.downloads;
          incomplete-dir = "${cfg.mediaDirs.downloads}/incomplete";
          watch-dir = "${cfg.mediaDirs.downloads}/watch";

          # Network settings
          peer-port = 51413;
          peer-port-random-on-start = true;

          # Security
          rpc-username = "transmission";
          rpc-password = "changeme"; # Should be overridden via SOPS

          # Performance
          cache-size-mb = 4;
          prefetch-enabled = true;

          # Limits
          speed-limit-down = 0;
          speed-limit-up = 0;
          ratio-limit = 2.0;
          ratio-limit-enabled = true;
        };

        # Open firewall
        openFirewall = true;
      };

      # Firewall rules - only allow necessary ports since we're behind Caddy
      networking.firewall = {
        allowedTCPPorts = [
          cfg.jellyfin.port    # Jellyfin
          9091                  # Transmission web interface
        ];
        allowedUDPPorts = [
          51413  # Transmission peer port
        ];
      };

      # Create users and groups
      users.users = {
        # Jellyfin user
        jellyfin = mkIf cfg.jellyfin.enable {
          isSystemUser = true;
          group = "jellyfin";
          home = cfg.jellyfin.dataDir;
          createHome = true;
        };

        # Sonarr user
        sonarr = mkIf cfg.sonarr.enable {
          isSystemUser = true;
          group = "sonarr";
          home = cfg.sonarr.dataDir;
          createHome = true;
        };

        # Radarr user
        radarr = mkIf cfg.radarr.enable {
          isSystemUser = true;
          group = "radarr";
          home = cfg.radarr.dataDir;
          createHome = true;
        };

        # Prowlarr user
        prowlarr = mkIf cfg.prowlarr.enable {
          isSystemUser = true;
          group = "prowlarr";
          home = cfg.prowlarr.dataDir;
          createHome = true;
        };

        # Transmission user
        transmission = {
          isSystemUser = true;
          group = "transmission";
          home = "/var/lib/transmission";
          createHome = true;
        };
      };

      users.groups = {
        # Jellyfin group
        jellyfin = mkIf cfg.jellyfin.enable {};

        # Sonarr group
        sonarr = mkIf cfg.sonarr.enable {};

        # Radarr group
        radarr = mkIf cfg.radarr.enable {};

        # Prowlarr group
        prowlarr = mkIf cfg.prowlarr.enable {};

        # Transmission group
        transmission = {};

        # Media group for shared access
        media = {
          members = mkMerge [
            (mkIf cfg.jellyfin.enable [ "jellyfin" ])
            (mkIf cfg.sonarr.enable [ "sonarr" ])
            (mkIf cfg.radarr.enable [ "radarr" ])
            (mkIf cfg.prowlarr.enable [ "prowlarr" ])
            [ "transmission" ]
          ];
        };
      };

      # Create media directories
      systemd.tmpfiles.rules = [
        # Media directories
        "d ${cfg.mediaDirs.movies} 0755 root media"
        "d ${cfg.mediaDirs.tv} 0755 root media"
        "d ${cfg.mediaDirs.music} 0755 root media"
        "d ${cfg.mediaDirs.downloads} 0755 transmission media"
        "d ${cfg.mediaDirs.torrents} 0755 transmission media"

        # Service directories
        "d ${cfg.jellyfin.dataDir} 0755 jellyfin jellyfin"
        "d ${cfg.jellyfin.cacheDir} 0755 jellyfin jellyfin"
        "d ${cfg.jellyfin.logDir} 0755 jellyfin jellyfin"
      ] ++ (lib.optional cfg.sonarr.enable "d ${cfg.sonarr.dataDir} 0755 sonarr sonarr")
          ++ (lib.optional cfg.radarr.enable "d ${cfg.radarr.dataDir} 0755 radarr radarr")
          ++ (lib.optional cfg.prowlarr.enable "d ${cfg.prowlarr.dataDir} 0755 prowlarr prowlarr");

      # Systemd services and health checks
      systemd.services = {
        # Jellyfin service
        jellyfin = mkIf cfg.jellyfin.enable {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        # Sonarr service
        sonarr = mkIf cfg.sonarr.enable {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        # Radarr service
        radarr = mkIf cfg.radarr.enable {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        # Prowlarr service
        prowlarr = mkIf cfg.prowlarr.enable {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        # Transmission service
        transmission = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        # Health checks
        # Jellyfin health check
        "jellyfin-health" = mkIf cfg.jellyfin.enable {
          description = "Jellyfin health check";
          wantedBy = [ "multi-user.target" ];
          after = [ "jellyfin.service" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.jellyfin.port}/health";
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };

        # Sonarr health check
        "sonarr-health" = mkIf cfg.sonarr.enable {
          description = "Sonarr health check";
          wantedBy = [ "multi-user.target" ];
          after = [ "sonarr.service" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.sonarr.port}/health";
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };

        # Radarr health check
        "radarr-health" = mkIf cfg.radarr.enable {
          description = "Radarr health check";
          wantedBy = [ "multi-user.target" ];
          after = [ "radarr.service" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.radarr.port}/health";
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };

        # Prowlarr health check
        "prowlarr-health" = mkIf cfg.prowlarr.enable {
          description = "Prowlarr health check";
          wantedBy = [ "multi-user.target" ];
          after = [ "prowlarr.service" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.prowlarr.port}/health";
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };
      };

      # Default configuration
      services.nixmox.media = {
        jellyfin.enable = true;
        sonarr.enable = false;  # Temporarily disabled due to database config issues
        radarr.enable = false;  # Temporarily disabled due to database config issues
        prowlarr.enable = false; # Temporarily disabled due to database config issues
      };
    });
  } 