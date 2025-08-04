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
    
    # Postfix configuration
    postfix = {
      hostname = mkOption {
        type = types.str;
        default = "mail.nixmox.lan";
        description = "Postfix hostname";
      };
      
      mydomain = mkOption {
        type = types.str;
        default = "nixmox.lan";
        description = "Postfix mydomain";
      };
      
      myorigin = mkOption {
        type = types.str;
        default = "nixmox.lan";
        description = "Postfix myorigin";
      };
      
      mydestination = mkOption {
        type = types.listOf types.str;
        default = [ "localhost" "localhost.localdomain" "nixmox.lan" "mail.nixmox.lan" ];
        description = "Postfix mydestination";
      };
      
      mynetworks = mkOption {
        type = types.listOf types.str;
        default = [ "127.0.0.0/8" "192.168.50.0/24" "10.0.0.0/8" "172.16.0.0/12" ];
        description = "Postfix trusted networks";
      };
    };
    
    # Dovecot configuration
    dovecot = {
      protocols = mkOption {
        type = types.listOf types.str;
        default = [ "imap" "sieve" "lmtp" ];
        description = "Dovecot protocols to enable";
      };
      
      mailLocation = mkOption {
        type = types.str;
        default = "maildir:~/Maildir";
        description = "Dovecot mail location";
      };
    };
    
    # User management
    users = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Username";
          };
          email = mkOption {
            type = types.str;
            description = "Email address";
          };
          password = mkOption {
            type = types.str;
            default = "changeme";
            description = "User password (should be overridden via SOPS)";
          };
        };
      });
      default = [];
      description = "Mail users to create";
    };
  };

  config = mkIf cfg.enable {
    # Postfix configuration
    services.postfix = {
      enable = true;
      
      # Basic settings
      hostName = cfg.postfix.hostname;
      domain = cfg.postfix.mydomain;
      origin = cfg.postfix.myorigin;
      destination = cfg.postfix.mydestination;
      networks = cfg.postfix.mynetworks;
      
      # TLS settings
      enableSubmission = true;
      enableSubmissions = true;
      
      # Authentication settings
      enableSmtp = true;
      
      # Relay settings
      relayDomains = [ cfg.primaryDomain ];
      
      # Security settings
      config = {
        # Basic settings
        myhostname = cfg.postfix.hostname;
        mydomain = cfg.postfix.mydomain;
        myorigin = cfg.postfix.myorigin;
        mydestination = lib.concatStringsSep ", " cfg.postfix.mydestination;
        mynetworks = lib.concatStringsSep ", " cfg.postfix.mynetworks;
        
        # TLS settings
        smtpd_tls_cert_file = "/var/lib/postfix/certs/cert.pem";
        smtpd_tls_key_file = "/var/lib/postfix/certs/key.pem";
        smtpd_tls_security_level = "may";
        smtpd_tls_auth_only = "yes";
        smtpd_tls_received_header = "yes";
        smtpd_tls_session_cache_database = "btree:${data_directory}/smtpd_scache";
        smtp_tls_session_cache_database = "btree:${data_directory}/smtp_scache";
        
        # Authentication
        smtpd_sasl_auth_enable = "yes";
        smtpd_sasl_security_options = "noanonymous";
        smtpd_sasl_local_domain = cfg.primaryDomain;
        smtpd_recipient_restrictions = "permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination";
        
        # Dovecot integration
        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "private/auth";
        
        # Virtual domains
        virtual_transport = "lmtp:unix:private/dovecot-lmtp";
        virtual_mailbox_domains = cfg.primaryDomain;
        virtual_mailbox_maps = "hash:/var/lib/postfix/virtual";
        virtual_alias_maps = "hash:/var/lib/postfix/virtual";
        
        # Performance
        inet_interfaces = "all";
        inet_protocols = "all";
        message_size_limit = "10485760";
        mailbox_size_limit = "0";
        home_mailbox = "Maildir/";
        
        # Logging
        mail_name = "NixMox Mail Server";
      };
    };
    
    # Dovecot configuration
    services.dovecot2 = {
      enable = true;
      
      # Protocols
      protocols = cfg.dovecot.protocols;
      
      # Modules
      modules = [ "dovecot_imap" "dovecot_sieve" "dovecot_lmtp" ];
      
      # Settings
      settings = {
        # Basic settings
        protocols = lib.concatStringsSep " " cfg.dovecot.protocols;
        listen = [ "*" ];
        
        # SSL/TLS
        ssl = "required";
        ssl_cert = "</var/lib/postfix/certs/cert.pem";
        ssl_key = "</var/lib/postfix/certs/key.pem";
        ssl_protocols = "!SSLv2 !SSLv3";
        ssl_cipher_list = "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384";
        
        # Authentication
        auth_mechanisms = "plain login";
        auth_default_realm = cfg.primaryDomain;
        
        # Mail location
        mail_location = cfg.dovecot.mailLocation;
        
        # User database
        userdb = {
          driver = "passwd";
        };
        
        passdb = {
          driver = "pam";
        };
        
        # Postfix integration
        service.auth = {
          unix_listener = {
            auth = {
              mode = "0666";
            };
          };
        };
        
        service.lmtp = {
          unix_listener = {
            dovecot-lmtp = {
              mode = "0666";
            };
          };
        };
        
        # IMAP settings
        protocol.imap = {
          mail_plugins = "sieve";
        };
        
        # LMTP settings
        protocol.lmtp = {
          mail_plugins = "sieve";
        };
        
        # Sieve settings
        plugin.sieve = "file:~/sieve;active=~/.dovecot.sieve";
        
        # Logging
        log_path = "/var/log/dovecot.log";
        info_log_path = "/var/log/dovecot-info.log";
        debug_log_path = "/var/log/dovecot-debug.log";
      };
    };
    
    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        25   # SMTP
        465  # SMTPS
        587  # Submission
        993  # IMAPS
        995  # POP3S
      ];
    };
    
    # Systemd services
    systemd.services = {
      # Postfix service
      "postfix" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      
      # Dovecot service
      "dovecot2" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
    };
    
    # Create mail users
    users.users = mkMerge (map (user: {
      "${user.name}" = {
        isNormalUser = true;
        group = "mail";
        extraGroups = [ "mail" ];
        home = "/var/mail/${user.name}";
        createHome = true;
        # Password will be set via SOPS
        hashedPassword = user.password;
      };
    }) cfg.users);
    
    # Create mail group
    users.groups.mail = {};
    
    # Create mail directories
    systemd.tmpfiles.rules = [
      "d /var/mail 0755 root mail"
      "d /var/lib/postfix 0755 postfix postfix"
      "d /var/lib/postfix/certs 0755 postfix postfix"
      "d /var/lib/postfix/virtual 0755 postfix postfix"
    ] ++ (map (user: "d /var/mail/${user.name} 0755 ${user.name} mail") cfg.users);
    
    # Health checks
    systemd.services.postfix-health = {
      description = "Postfix health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "postfix.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f telnet://localhost:25";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
    systemd.services.dovecot-health = {
      description = "Dovecot health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "dovecot2.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f telnet://localhost:993";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
    # Default mail users
    services.nixmox.mail.users = [
      {
        name = "admin";
        email = "admin@${cfg.primaryDomain}";
        password = "changeme";
      }
      {
        name = "postmaster";
        email = "postmaster@${cfg.primaryDomain}";
        password = "changeme";
      }
    ];
  };
} 