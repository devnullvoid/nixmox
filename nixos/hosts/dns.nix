{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.dns;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # DNS service module
    ../modules/dns
  ];

  # Host-specific configuration
  networking.hostName = "dns";
  
  # Enable DNS service
  services.nixmox.dns.enable = true;

  # Firewall rules for DNS
  networking.firewall = {
    allowedTCPPorts = [
      53 # DNS
    ];
    allowedUDPPorts = [
      53 # DNS
    ];
  };
}
