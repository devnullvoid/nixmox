{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.guacamole;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Guacamole service module
    ../modules/guacamole
  ];

  # Host-specific configuration
  networking.hostName = "guacamole";
  
  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Enable Guacamole service
  services.nixmox.guacamole.enable = true;

  # Use external PostgreSQL
  services.nixmox.guacamole.database = {
    host = "postgresql.nixmox.lan";
    port = 5432;
    name = "guacamole";
    user = "guacamole";
    password = "changeme"; # Should be overridden via SOPS
  };

  # Firewall rules - only allow backend access since we're behind Caddy
  networking.firewall = {
    allowedTCPPorts = [
      8280 # Tomcat/Guacamole
    ];
  };
}
