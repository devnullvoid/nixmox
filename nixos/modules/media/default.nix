{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.media;
  
  # Get service configurations from manifest
  serviceConfig = manifest.services.media or {};
  
  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Determine effective hostname
  hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${baseDomain}";
in {
  imports = [
    ./jellyfin.nix
    ./sonarr.nix
    ./radarr.nix
    ./prowlarr.nix
    ./transmission.nix
  ];

  options.services.nixmox.media = {
    enable = mkEnableOption "Media stack (Jellyfin + Sonarr + Radarr + Prowlarr + Transmission)";
    
    subdomain = mkOption {
      type = types.str;
      default = "media";
      description = "Subdomain for media services; full host becomes <subdomain>.<services.nixmox.domain>";
    };

    hostName = mkOption {
      type = types.str;
      default = proxyConfig.jellyfin.domain or "jellyfin.nixmox.lan";
      description = "Public host name for media services (from manifest proxy config)";
    };

    # Component enablement options are defined in their respective files
    # jellyfin = { ... } - defined in jellyfin.nix
    # sonarr = { ... } - defined in sonarr.nix
    # radarr = { ... } - defined in radarr.nix
    # prowlarr = { ... } - defined in prowlarr.nix
    # transmission = { ... } - defined in transmission.nix

    # Shared configuration options
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/media";
      description = "Base data directory for media services";
    };

    cacheDir = mkOption {
      type = types.str;
      default = "/var/cache/media";
      description = "Base cache directory for media services";
    };

    logDir = mkOption {
      type = types.str;
      default = "/var/log/media";
      description = "Base log directory for media services";
    };

    # Torrents directory
    torrentsDir = mkOption {
      type = types.str;
      default = "/var/lib/media/torrents";
      description = "Torrents directory";
    };

    # Database configuration for each service
    databases = {
      jellyfin = {
        type = mkOption {
          type = types.enum [ "postgresql" "sqlite" ];
          default = "postgresql";
          description = "Jellyfin database type";
        };

        host = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.jellyfin.host or "postgresql.nixmox.lan";
          description = "Jellyfin database host (from manifest)";
        };

        port = mkOption {
          type = types.int;
          default = serviceConfig.interface.dbs.jellyfin.port or 5432;
          description = "Jellyfin database port (from manifest)";
        };

        name = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.jellyfin.name or "jellyfin";
          description = "Jellyfin database name (from manifest)";
        };

        user = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.jellyfin.owner or "jellyfin";
          description = "Jellyfin database user (from manifest)";
        };
      };

      sonarr = {
        type = mkOption {
          type = types.enum [ "postgresql" "sqlite" ];
          default = "postgresql";
          description = "Sonarr database type";
        };

        host = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.sonarr.host or "postgresql.nixmox.lan";
          description = "Sonarr database host (from manifest)";
        };

        port = mkOption {
          type = types.int;
          default = serviceConfig.interface.dbs.sonarr.port or 5432;
          description = "Sonarr database port (from manifest)";
        };

        name = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.sonarr.name or "sonarr";
          description = "Sonarr database name (from manifest)";
        };

        user = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.sonarr.owner or "sonarr";
          description = "Sonarr database user (from manifest)";
        };
      };

      radarr = {
        type = mkOption {
          type = types.enum [ "postgresql" "sqlite" ];
          default = "postgresql";
          description = "Radarr database type";
        };

        host = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.radarr.host or "postgresql.nixmox.lan";
          description = "Radarr database host (from manifest)";
        };

        port = mkOption {
          type = types.int;
          default = serviceConfig.interface.dbs.radarr.port or 5432;
          description = "Radarr database port (from manifest)";
        };

        name = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.radarr.name or "radarr";
          description = "Radarr database name (from manifest)";
        };

        user = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.radarr.owner or "radarr";
          description = "Radarr database user (from manifest)";
        };
      };

      prowlarr = {
        type = mkOption {
          type = types.enum [ "postgresql" "sqlite" ];
          default = "postgresql";
          description = "Prowlarr database type";
        };

        host = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.prowlarr.host or "postgresql.nixmox.lan";
          description = "Prowlarr database host (from manifest)";
        };

        port = mkOption {
          type = types.int;
          default = serviceConfig.interface.dbs.prowlarr.port or 5432;
          description = "Prowlarr database port (from manifest)";
        };

        name = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.prowlarr.name or "prowlarr";
          description = "Prowlarr database name (from manifest)";
        };

        user = mkOption {
          type = types.str;
          default = serviceConfig.interface.dbs.prowlarr.owner or "prowlarr";
          description = "Prowlarr database user (from manifest)";
        };
      };
    };

    # Authentication is now handled per-proxy in the manifest
    # No global auth configuration needed
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${config.services.nixmox.domain}";
    in {
      # Ensure local resolution works even before DNS is in place
      networking.hosts = let
        # Collect unique database hosts
        dbHosts = lib.unique [
          cfg.databases.sonarr.host
          cfg.databases.radarr.host
          cfg.databases.prowlarr.host
        ];
        
        # Create host entries for non-localhost database hosts
        dbHostEntries = lib.foldl' (acc: host:
          if host != "localhost" then
            acc // { "${host}" = [ "postgresql.nixmox.lan" ]; }
          else
            acc
        ) {} dbHosts;
      in {
        "127.0.0.1" = [ hostNameEffective ];
      } // dbHostEntries;

      # Provide media-specific Caddy configurations via global option
      # This will be collected by the Caddy module when it's enabled
      services.nixmox.caddyServiceConfigs = {
        # Jellyfin configuration
        jellyfin = {
          extraConfig = ''
            # Jellyfin-specific headers
            header {
              # Enable CORS
              Access-Control-Allow-Origin "*"
              Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
              Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization"
              
              # Security headers
              X-Content-Type-Options nosniff
              X-Frame-Options DENY
              X-XSS-Protection "1; mode=block"
            }
            
            # Handle preflight requests
            @options {
              method OPTIONS
            }
            respond @options 200
          '';
        };
        
        # Sonarr configuration
        sonarr = {
          extraConfig = ''
            # Security headers
            header {
              X-Content-Type-Options nosniff
              X-Frame-Options DENY
              X-XSS-Protection "1; mode=block"
            }
          '';
        };
        
        # Radarr configuration
        radarr = {
          extraConfig = ''
            # Security headers
            header {
              X-Content-Type-Options nosniff
              X-Frame-Options DENY
              X-XSS-Protection "1; mode=block"
            }
          '';
        };
        
        # Prowlarr configuration
        prowlarr = {
          extraConfig = ''
            # Security headers
            header {
              X-Content-Type-Options nosniff
              X-Frame-Options DENY
              X-XSS-Protection "1; mode=block"
            }
          '';
        };
        
        # Transmission configuration
        transmission = {
          extraConfig = ''
            # Security headers
            header {
              X-Content-Type-Options nosniff
              X-Frame-Options DENY
              X-XSS-Protection "1; mode=block"
            }
          '';
        };
      };

      # Default configuration - enable all components
      services.nixmox.media = {
        jellyfin.enable = false;
        sonarr.enable = false;
        radarr.enable = false;
        prowlarr.enable = false;
        transmission.enable = true;
      };
    }
  );
}