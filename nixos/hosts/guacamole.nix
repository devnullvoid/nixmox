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
  
  # Add PostgreSQL client tools for database schema import
  environment.systemPackages = with pkgs; [
    postgresql
  ];
  
  # Enable Guacamole service
  services.nixmox.guacamole.enable = true;

  # Configure Guacamole for guac.nixmox.lan domain
  services.nixmox.guacamole = {
    subdomain = "guac";
    hostName = "guac.nixmox.lan";
    authentikDomain = "auth.nixmox.lan";
    oidcProviderPath = "guacamole";
    clientId = "guacamole-client";
  };

  # Use external PostgreSQL
  services.nixmox.guacamole.database = {
    host = "192.168.99.11";  # Use IP instead of hostname to avoid DNS issues
    port = 5432;
    name = "guacamole";
    user = "guacamole";
    password = "guacamole123"; # TODO: Use SOPS for production
  };

  # Firewall rules - only allow backend access since we're behind Caddy
  networking.firewall = {
    allowedTCPPorts = [
      8280 # Tomcat/Guacamole
    ];
  };
}
