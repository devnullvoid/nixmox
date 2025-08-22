{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.vaultwarden;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Vaultwarden service module
    ../modules/vaultwarden
    ../modules/vaultwarden/oci.nix
  ];

  # Host-specific configuration
  networking.hostName = "vaultwarden";
  
  # Enable Vaultwarden OCI service
  services.nixmox.vaultwarden.oci.enable = true;

  # Firewall rules - only allow backend access since we're behind Caddy
  networking.firewall = {
    allowedTCPPorts = [
      8080 # Vaultwarden web interface
    ];
  };
}
