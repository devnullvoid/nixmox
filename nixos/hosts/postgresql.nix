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

  # Configure databases and users
  services.nixmox.postgresql = {
    # Create Authentik database and user
    databases.authentik = {
      name = "authentik";
      owner = "authentik";
      extensions = [ "uuid-ossp" "pgcrypto" ];
    };

    users.authentik = {
      name = "authentik";
      password = "authentik123"; # TODO: Use SOPS for production - will be overridden by Authentik service
      databases = [ "authentik" ];
      superuser = false;
    };

    # Create Guacamole database and user
    databases.guacamole = {
      name = "guacamole";
      owner = "guacamole";
      extensions = [];
    };

    users.guacamole = {
      name = "guacamole";
      password = "guacamole123"; # TODO: Use SOPS for production
      databases = [ "guacamole" ];
      superuser = false;
    };
  };

  # Firewall rules for PostgreSQL
  networking.firewall = {
    allowedTCPPorts = [
      cfg.port  # PostgreSQL
    ];
  };
}
