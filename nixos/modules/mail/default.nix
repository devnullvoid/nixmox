{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.mail;

  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";

  # Get service configuration from manifest
  serviceConfig = manifest.services.mail or {};

  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};
in {
  options.services.nixmox.mail = {
    enable = mkEnableOption "Mail server (Postfix + Dovecot)";
    
    domain = mkOption {
      type = types.str;
      default = proxyConfig.domain or "mail.nixmox.lan";
      description = "Domain for mail service (from manifest proxy config)";
    };

    primaryDomain = mkOption {
      type = types.str;
      default = baseDomain;
      description = "Primary domain for mail (from manifest network config)";
    };
  };

  config = mkIf cfg.enable {
    # Basic mail services - simplified configuration for now
    services.postfix = {
      enable = true;
      enableSubmission = true;
      enableSubmissions = true;
      enableSmtp = true;
    };
    
    services.dovecot2 = {
      enable = true;
      protocols = [ "imap" "sieve" "lmtp" ];
      mailLocation = "maildir:~/Maildir";
    };
    
    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        25   # SMTP
        587  # Submission
        465  # SMTPS
        143  # IMAP
        993  # IMAPS
        4190 # LMTP
      ];
    };
    
    # Basic systemd services
    systemd.services = {
      "postfix" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      
      "dovecot" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
} 