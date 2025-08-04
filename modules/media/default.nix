{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.media;
in {
  options.services.nixmox.media = {
    enable = mkEnableOption "Media server (Jellyfin + Arr stack)";
    
    domain = mkOption {
      type = types.str;
      default = "media.nixmox.lan";
      description = "Domain for media services";
    };
    
    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for services";
    };
    
    # Jellyfin configuration
    jellyfin = {
      enable = mkEnableOption "Jellyfin media server";
      
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
      enable = mkEnableOption "Sonarr TV show management";
      
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
    
    # Prowlarr configuration
    prowlarr = {
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
    
    # Media directories
    mediaDirs = mkOption {
      type = types.attrsOf types.str;
      default = {
        movies = "/var/media/movies";
        tv = "/var/media/tv";
        music = "/var/media/music";
        downloads = "/var/media/downloads";
        torrents = "/var/media/torrents";
      };
      description = "Media directories";
    };
  };

  config = mkIf cfg.enable {
    # Jellyfin configuration
    services.jellyfin = mkIf cfg.jellyfin.enable {
      enable = true;
      
      # User and group
      user = "jellyfin";
      group = "jellyfin";
      
      # Data directories
      dataDir = cfg.jellyfin.dataDir;
      cacheDir = cfg.jellyfin.cacheDir;
      logDir = cfg.jellyfin.logDir;
      
      # Open firewall
      openFirewall = true;
    };
    
    # Sonarr configuration
    services.sonarr = mkIf cfg.sonarr.enable {
      enable = true;
      
      # User and group
      user = "sonarr";
      group = "sonarr";
      
      # Data directory
      dataDir = cfg.sonarr.dataDir;
      
      # Open firewall
      openFirewall = true;
    };
    
    # Radarr configuration
    services.radarr = mkIf cfg.radarr.enable {
      enable = true;
      
      # User and group
      user = "radarr";
      group = "radarr";
      
      # Data directory
      dataDir = cfg.radarr.dataDir;
      
      # Open firewall
      openFirewall = true;
    };
    
    # Prowlarr configuration
    services.prowlarr = mkIf cfg.prowlarr.enable {
      enable = true;
      
      # User and group
      user = "prowlarr";
      group = "prowlarr";
      
      # Data directory
      dataDir = cfg.prowlarr.dataDir;
      
      # Open firewall
      openFirewall = true;
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
    
    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        cfg.jellyfin.port    # Jellyfin
        cfg.sonarr.port      # Sonarr
        cfg.radarr.port      # Radarr
        cfg.prowlarr.port    # Prowlarr
        9091                 # Transmission web interface
        51413                # Transmission peer port
      ];
      allowedUDPPorts = [
        51413  # Transmission peer port
      ];
    };
    
    # Create users and groups
    users.users = mkMerge [
      # Jellyfin user
      (mkIf cfg.jellyfin.enable {
        jellyfin = {
          isSystemUser = true;
          group = "jellyfin";
          home = cfg.jellyfin.dataDir;
          createHome = true;
        };
      })
      
      # Sonarr user
      (mkIf cfg.sonarr.enable {
        sonarr = {
          isSystemUser = true;
          group = "sonarr";
          home = cfg.sonarr.dataDir;
          createHome = true;
        };
      })
      
      # Radarr user
      (mkIf cfg.radarr.enable {
        radarr = {
          isSystemUser = true;
          group = "radarr";
          home = cfg.radarr.dataDir;
          createHome = true;
        };
      })
      
      # Prowlarr user
      (mkIf cfg.prowlarr.enable {
        prowlarr = {
          isSystemUser = true;
          group = "prowlarr";
          home = cfg.prowlarr.dataDir;
          createHome = true;
        };
      })
      
      # Transmission user
      {
        transmission = {
          isSystemUser = true;
          group = "transmission";
          home = "/var/lib/transmission";
          createHome = true;
        };
      }
    ];
    
    users.groups = mkMerge [
      # Jellyfin group
      (mkIf cfg.jellyfin.enable {
        jellyfin = {};
      })
      
      # Sonarr group
      (mkIf cfg.sonarr.enable {
        sonarr = {};
      })
      
      # Radarr group
      (mkIf cfg.radarr.enable {
        radarr = {};
      })
      
      # Prowlarr group
      (mkIf cfg.prowlarr.enable {
        prowlarr = {};
      })
      
      # Transmission group
      {
        transmission = {};
      }
      
      # Media group for shared access
      {
        media = {
          members = mkMerge [
            (mkIf cfg.jellyfin.enable [ "jellyfin" ])
            (mkIf cfg.sonarr.enable [ "sonarr" ])
            (mkIf cfg.radarr.enable [ "radarr" ])
            (mkIf cfg.prowlarr.enable [ "prowlarr" ])
            [ "transmission" ]
          ];
        };
      }
    ];
    
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
    ] ++ (mkIf cfg.sonarr.enable [
      "d ${cfg.sonarr.dataDir} 0755 sonarr sonarr"
    ]) ++ (mkIf cfg.radarr.enable [
      "d ${cfg.radarr.dataDir} 0755 radarr radarr"
    ]) ++ (mkIf cfg.prowlarr.enable [
      "d ${cfg.prowlarr.dataDir} 0755 prowlarr prowlarr"
    ]);
    
    # Systemd services and health checks
    systemd.services = mkMerge [
      # Jellyfin service
      (mkIf cfg.jellyfin.enable {
        "jellyfin" = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };
      })
      
      # Sonarr service
      (mkIf cfg.sonarr.enable {
        "sonarr" = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };
      })
      
      # Radarr service
      (mkIf cfg.radarr.enable {
        "radarr" = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };
      })
      
      # Prowlarr service
      (mkIf cfg.prowlarr.enable {
        "prowlarr" = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };
      })
      
      # Transmission service
      {
        "transmission" = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };
      }
      
      # Health checks
      # Jellyfin health check
      (mkIf cfg.jellyfin.enable {
        "jellyfin-health" = {
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
      })
      
      # Sonarr health check
      (mkIf cfg.sonarr.enable {
        "sonarr-health" = {
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
      })
      
      # Radarr health check
      (mkIf cfg.radarr.enable {
        "radarr-health" = {
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
      })
      
      # Prowlarr health check
      (mkIf cfg.prowlarr.enable {
        "prowlarr-health" = {
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
      })

    
    # Default configuration
    services.nixmox.media = {
      jellyfin.enable = true;
      sonarr.enable = true;
      radarr.enable = true;
      prowlarr.enable = true;
    };
  };
} 