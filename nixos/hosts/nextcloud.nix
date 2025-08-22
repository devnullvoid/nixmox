{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.nextcloud;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Nextcloud service module
    ../modules/nextcloud
  ];

  # Host-specific configuration
  networking.hostName = "nextcloud";
  
  # Enable Nextcloud service
  services.nixmox.nextcloud.enable = true;

  # Use external PostgreSQL
  services.nixmox.nextcloud.database = {
    type = "postgresql";
    host = "postgresql.nixmox.lan";
    port = 5432;
    name = "nextcloud";
    user = "nextcloud";
    password = "changeme"; # Should be overridden via SOPS
  };

  # Firewall rules - only allow backend access since we're behind Caddy
  networking.firewall = {
    allowedTCPPorts = [
      8080  # Nextcloud backend (behind Caddy)
    ];
  };
}
