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

    # Authentication is now handled per-proxy in the manifest
    # No global auth configuration needed
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${config.services.nixmox.domain}";
    in {
      # Ensure local resolution works even before DNS is in place
      networking.hosts = {
        "127.0.0.1" = [ hostNameEffective ];
      };

      # Provide media-specific Caddy configurations via global option
      # This will be collected by the Caddy module when it's enabled

      # Default configuration - enable all components
      services.nixmox.media = {
        jellyfin.enable = true;
        sonarr.enable = true;
        radarr.enable = true;
        prowlarr.enable = true;
        transmission.enable = true;
      };
    }
  );
}