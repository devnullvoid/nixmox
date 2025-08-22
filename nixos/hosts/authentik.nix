{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.authentik;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Authentik service module
    ../modules/authentik
  ];

  # Host-specific configuration
  networking.hostName = "authentik";
  
  # Enable Authentik service
  services.nixmox.authentik.enable = true;

  # Firewall rules for Authentik services
  networking.firewall = {
    allowedTCPPorts = [
      389  # LDAP
      636  # LDAPS
      9000 # Authentik HTTP
      9443 # Authentik HTTPS
    ];
    allowedUDPPorts = [
      1812 # RADIUS
      1813 # RADIUS accounting
    ];
  };
}
