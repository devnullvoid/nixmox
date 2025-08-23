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
  
  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Enable Authentik service
  services.nixmox.authentik.enable = true;

  # Configure Authentik service
  services.nixmox.authentik = {
    # Set subdomain for Authentik
    subdomain = "auth";
    
    # Set admin email
    adminEmail = "admin@nixmox.lan";
    
    # Database configuration
    database = {
      host = "postgresql.nixmox.lan";
      port = 5432;
      name = "authentik";
      user = "authentik";
      password = "authentik123"; # TODO: Use SOPS for production
    };
    
    # Redis configuration
    redis = {
      host = "localhost";
      port = 6379;
    };
  };

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
