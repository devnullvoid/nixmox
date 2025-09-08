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
    enable = mkEnableOption "Mail server using NixOS Mailserver";
    
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

    # Mail accounts configuration
    accounts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          hashedPassword = mkOption {
            type = types.str;
            description = "Hashed password for the mail account";
          };
          aliases = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Email aliases for this account";
          };
        };
      });
      default = {};
      description = "Mail accounts configuration";
    };

    # Roundcube webmail configuration
    roundcube = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Roundcube webmail interface";
      };
    };
  };

  config = mkIf cfg.enable {
    # Import NixOS Mailserver
    imports = [
      (builtins.fetchTarball {
        url = "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/nixos-25.05/nixos-mailserver-nixos-25.05.tar.gz";
        sha256 = "0000000000000000000000000000000000000000000000000000";
      })
    ];

    # NixOS Mailserver configuration
    mailserver = {
      enable = true;
      fqdn = cfg.domain;
      domains = [ cfg.primaryDomain ];
      
      # Use internal CA certificates
      certificateScheme = "manual";
      certificateFile = "/etc/ssl/certs/wildcard.crt";
      keyFile = "/etc/ssl/private/wildcard.key";
      
      # Login accounts - will be populated from SOPS secrets
      loginAccounts = builtins.mapAttrs (email: account: {
        hashedPasswordFile = account.hashedPassword;
        aliases = account.aliases;
      }) cfg.accounts;
      
      # Enable additional features
      enableImap = true;
      enablePop3 = false;
      enableSubmission = true;
      enableSubmissions = true;
      enableManageSieve = true;
      enableImapSieve = true;
      
      # Security settings
      virusScanning = true;
      virusScanningDaemon = "clamav";
      
      # Spam filtering
      enableSpamAssassin = true;
      enableRspamd = true;
      
      # DKIM signing
      enableDKIM = true;
      dkimSelector = "mail";
      
      # Full text search
      enableFTS = true;
      
      # Webmail (Roundcube)
      enableRoundcube = cfg.roundcube.enable;
      roundcubePlugins = [
        "password"
        "managesieve"
        "archive"
        "zipdownload"
      ];
      
      # Roundcube configuration
      roundcubeExtraConfig = ''
        $config['product_name'] = 'NixMox Mail';
        $config['support_url'] = 'https://${cfg.domain}/support';
        $config['skin'] = 'elastic';
        $config['default_host'] = 'ssl://${cfg.domain}';
        $config['default_port'] = 993;
        $config['imap_cache'] = 'db';
        $config['messages_cache'] = 'db';
        $config['enable_installer'] = false;
        $config['log_driver'] = 'file';
        $config['log_date_format'] = 'Y-m-d H:i:s';
      '';
    };

    # Firewall rules for mail services
    networking.firewall = {
      allowedTCPPorts = [
        25   # SMTP
        587  # Submission
        465  # SMTPS
        143  # IMAP
        993  # IMAPS
        110  # POP3 (if enabled)
        995  # POP3S (if enabled)
        4190 # ManageSieve
        80   # HTTP (for Roundcube)
        443  # HTTPS (for Roundcube)
      ];
    };

    # Caddy service configuration for Roundcube
    services.nixmox.caddyServiceConfigs.mail = mkIf cfg.roundcube.enable {
      extraConfig = ''
        ${cfg.domain} {
          reverse_proxy localhost:80
          
          # Security headers
          header {
            X-Content-Type-Options nosniff
            X-Frame-Options DENY
            X-XSS-Protection "1; mode=block"
            Strict-Transport-Security "max-age=31536000; includeSubDomains"
          }
        }
      '';
    };

    # Default mail accounts (can be overridden)
    services.nixmox.mail.accounts = {
      "admin@${cfg.primaryDomain}" = {
        hashedPassword = config.sops.secrets."mail/admin_password".path;
        aliases = [ "postmaster@${cfg.primaryDomain}" "abuse@${cfg.primaryDomain}" ];
      };
    };

    # SOPS secrets for mail accounts
    sops.secrets."mail/admin_password" = {
      sopsFile = ../../secrets/default.yaml;
      owner = "dovecot2";
      group = "dovecot2";
      mode = "0400";
    };
  };
} 