{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.media;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Media service module
    ../modules/media
  ];

  # Host-specific configuration
  networking.hostName = "media";
  
  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Enable media services
  services.nixmox.media.enable = true;

  # Use external PostgreSQL
  services.nixmox.media.database = {
    type = "postgresql";
    host = "postgresql.nixmox.lan";
    port = 5432;
    name = "media";
    user = "media";
    password = "changeme"; # Should be overridden via SOPS
  };

  # Firewall rules - only allow backend access since we're behind Caddy
  networking.firewall = {
    allowedTCPPorts = [
      8096  # Jellyfin backend (behind Caddy)
      8989  # Sonarr backend (behind Caddy)
      7878  # Radarr backend (behind Caddy)
      9696  # Prowlarr backend (behind Caddy)
      9091  # Transmission web interface
    ];
    allowedUDPPorts = [
      51413  # Transmission peer port
    ];
  };
}
