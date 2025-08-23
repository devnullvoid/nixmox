{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Caddy service module
    ../modules/caddy
    ../modules/localtls
  ];

  # Host-specific configuration
  networking.hostName = "caddy";
  
  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Enable Caddy service
  services.nixmox.caddy = {
    enable = true;
    developmentMode = true; # Disable automatic HTTPS for development
  };
  services.nixmox.localtls.enable = true;

  # Firewall rules for Caddy
  networking.firewall = {
    allowedTCPPorts = [
      80   # HTTP
      443  # HTTPS
      9090 # Caddy metrics
    ];
  };
}
