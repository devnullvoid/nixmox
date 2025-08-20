{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.mail;
in {
  options.services.nixmox.mail = {
    enable = mkEnableOption "Mail server (Postfix + Dovecot)";
    
    domain = mkOption {
      type = types.str;
      default = "mail.nixmox.lan";
      description = "Domain for mail service";
    };
    
    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for mail";
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