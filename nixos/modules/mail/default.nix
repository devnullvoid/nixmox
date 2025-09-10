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
    enable = mkEnableOption "Basic SMTP relay with Mailrise notification forwarding";

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

    # SMTP relay configuration
    relayHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SMTP relay host for outbound mail (e.g., smtp.gmail.com)";
    };

    relayPort = mkOption {
      type = types.int;
      default = 587;
      description = "SMTP relay port";
    };

    relayUser = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SMTP relay username";
    };

    relayPasswordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to file containing SMTP relay password";
    };

    # Mailrise notification forwarding
    mailrise = {
      enable = mkEnableOption "Mailrise notification forwarding";

      port = mkOption {
        type = types.int;
        default = 8025;
        description = "Port for Mailrise SMTP server";
      };

      configFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Path to Mailrise configuration file (YAML format).
          Example configuration:
          ---
          urls:
            # Send all emails to Discord
            "*": "discord://token@channel"
            # Send specific sender emails to Slack
            "alert@myserver.com": "slack://token@channel"
            # Send emails to multiple services
            "backup@myserver.com": ["discord://...", "slack://..."]
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # Install mailrise package if enabled
    environment.systemPackages = lib.optional cfg.mailrise.enable pkgs.mailrise;

    # Basic Postfix SMTP relay configuration
    services.postfix = {
      enable = true;
      hostname = cfg.domain;
      domain = cfg.primaryDomain;

      # Basic SMTP relay configuration
      relayHost = mkIf (cfg.relayHost != null) cfg.relayHost;
      relayPort = cfg.relayPort;

      # SASL authentication for relay
      saslAuthEnable = cfg.relayUser != null;
      # saslPasswordFile = mkIf (cfg.relayPasswordFile != null) cfg.relayPasswordFile;

      # Basic configuration
      config = {
        myorigin = cfg.primaryDomain;
        mydestination = [ cfg.domain cfg.primaryDomain "localhost" ];

        # Allow relaying from local network
        mynetworks = [ "127.0.0.0/8" "192.168.99.0/24" "::1/128" ];

        # Basic security
        smtp_tls_security_level = "may";
        smtp_tls_loglevel = "1";
        smtp_sasl_security_options = "noanonymous";

        # Disable local delivery for relay-only setup
        local_recipient_maps = "";
        local_transport = "error:local delivery disabled";
      };

      # Master daemon configuration
      masterConfig = {
        smtp = {
          type = "inet";
          private = false;
          command = "smtpd";
        };
        submission = {
          type = "inet";
          private = false;
          command = "smtpd";
          args = [ "-o" "smtpd_tls_security_level=encrypt" "-o" "smtpd_sasl_auth_enable=yes" ];
        };
      };
    };

    # Mailrise for notification forwarding
    systemd.services.mailrise = mkIf cfg.mailrise.enable {
      description = "Mailrise SMTP to Apprise notification gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.mailrise}/bin/mailrise --config ${cfg.mailrise.configFile} --port ${toString cfg.mailrise.port}";
        Restart = "always";
        User = "mailrise";
        Group = "mailrise";
        WorkingDirectory = "/var/lib/mailrise";
        StateDirectory = "mailrise";
        StateDirectoryMode = "0750";
      };
    };

    # Create mailrise user
    users.users.mailrise = mkIf cfg.mailrise.enable {
      isSystemUser = true;
      group = "mailrise";
      home = "/var/lib/mailrise";
      createHome = true;
    };

    users.groups.mailrise = mkIf cfg.mailrise.enable {};

    # Firewall rules for SMTP relay
    networking.firewall = {
      allowedTCPPorts = [
        25   # SMTP
        587  # Submission
      ] ++ (lib.optional cfg.mailrise.enable cfg.mailrise.port); # Mailrise port if enabled
    };

    # SOPS secrets for relay authentication
    sops.secrets = mkIf (cfg.relayPasswordFile != null) {
      "mail/relay_password" = {
        sopsFile = ../../secrets/default.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };

    # Override relay password file if SOPS secret exists
    services.postfix.saslPasswordFile = mkIf (cfg.relayPasswordFile != null) config.sops.secrets."mail/relay_password".path;
  };
}