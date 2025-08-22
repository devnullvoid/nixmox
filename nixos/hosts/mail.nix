{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.mail;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Mail service module
    ../modules/mail
  ];

  # Host-specific configuration
  networking.hostName = "mail";
  
  # Enable mail services
  services.nixmox.mail.enable = true;

  # Firewall rules for mail services
  networking.firewall = {
    allowedTCPPorts = [
      25   # SMTP
      587  # SMTP submission
      465  # SMTPS
      143  # IMAP
      993  # IMAPS
      110  # POP3
      995  # POP3S
    ];
  };
}
