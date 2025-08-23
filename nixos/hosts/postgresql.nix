{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.postgresql;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # PostgreSQL service module
    ../modules/postgresql
  ];

  # Host-specific configuration
  networking.hostName = "postgresql";

  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Enable PostgreSQL service
  services.nixmox.postgresql.enable = true;

  # Firewall rules for PostgreSQL
  networking.firewall = {
    allowedTCPPorts = [
      cfg.port  # PostgreSQL
    ];
  };
}
