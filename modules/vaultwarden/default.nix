{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.vaultwarden;
in {
  options.services.nixmox.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager";
    
    domain = mkOption {
      type = types.str;
      default = "vaultwarden.nixmox.lan";
      description = "Domain for Vaultwarden service";
    };
    
    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for services";
    };
    
    # Vaultwarden configuration
    vaultwarden = {
      port = mkOption {
        type = types.int;
        default = 8080;
        description = "Vaultwarden web interface port";
      };
      
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/vaultwarden";
        description = "Vaultwarden data directory";
      };
      
      # Database configuration
      database = {
        url = mkOption {
          type = types.str;
          default = "sqlite:///data/db.sqlite3";
          description = "Database URL for Vaultwarden";
        };
      };
      
      # Web vault configuration
      webVault = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable web vault interface";
        };
        
        path = mkOption {
          type = types.str;
          default = "/var/lib/vaultwarden/web-vault";
          description = "Web vault files path";
        };
      };
      
      # Environment variables
      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Environment variables for Vaultwarden";
      };
      
      # Admin token
      adminToken = mkOption {
        type = types.str;
        default = "changeme";
        description = "Admin token for Vaultwarden (should be overridden via SOPS)";
      };
      
      # Domain settings
      domain = mkOption {
        type = types.str;
        default = "https://vault.nixmox.lan";
        description = "Domain for Vaultwarden";
      };
      
      # Security settings
      security = {
        # JWT secret
        jwtSecret = mkOption {
          type = types.str;
          default = "changeme";
          description = "JWT secret for Vaultwarden (should be overridden via SOPS)";
        };
        
        # Signups allowed
        signupsAllowed = mkOption {
          type = types.bool;
          default = false;
          description = "Allow new user signups";
        };
        
        # Invitations allowed
        invitationsAllowed = mkOption {
          type = types.bool;
          default = true;
          description = "Allow invitations";
        };
      };
      
      # Email settings
      email = {
        smtpHost = mkOption {
          type = types.str;
          default = "mail.nixmox.lan";
          description = "SMTP host for email";
        };
        
        smtpPort = mkOption {
          type = types.int;
          default = 587;
          description = "SMTP port for email";
        };
        
        smtpFrom = mkOption {
          type = types.str;
          default = "vaultwarden@nixmox.lan";
          description = "SMTP from address";
        };
        
        smtpUsername = mkOption {
          type = types.str;
          default = "vaultwarden";
          description = "SMTP username";
        };
        
        smtpPassword = mkOption {
          type = types.str;
          default = "changeme";
          description = "SMTP password (should be overridden via SOPS)";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Vaultwarden service
    services.vaultwarden = {
      enable = true;
      
      # Basic settings
      config = {
        # Domain
        DOMAIN = cfg.vaultwarden.domain;
        
        # Database
        DATABASE_URL = cfg.vaultwarden.database.url;
        
        # Admin token
        ADMIN_TOKEN = cfg.vaultwarden.adminToken;
        
        # Security
        JWT_SECRET = cfg.vaultwarden.security.jwtSecret;
        SIGNUPS_ALLOWED = cfg.vaultwarden.security.signupsAllowed;
        INVITATIONS_ALLOWED = cfg.vaultwarden.security.invitationsAllowed;
        
        # Email settings
        SMTP_HOST = cfg.vaultwarden.email.smtpHost;
        SMTP_PORT = toString cfg.vaultwarden.email.smtpPort;
        SMTP_FROM = cfg.vaultwarden.email.smtpFrom;
        SMTP_USERNAME = cfg.vaultwarden.email.smtpUsername;
        SMTP_PASSWORD = cfg.vaultwarden.email.smtpPassword;
        SMTP_SECURITY = "starttls";
        
        # Web vault
        WEB_VAULT_ENABLED = cfg.vaultwarden.webVault.enable;
        WEB_VAULT_FOLDER = cfg.vaultwarden.webVault.path;
        
        # Additional environment variables
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = toString cfg.vaultwarden.port;
        ROCKET_WORKERS = "10";
        
        # Logging
        LOG_LEVEL = "warn";
        
        # Performance
        ENABLE_DB_WAL = "true";
        ENABLE_EXTENDED_LOGGING = "true";
        
        # Security headers
        SECURITY_HEADERS = "true";
        
        # Additional custom environment variables
      } // cfg.vaultwarden.environment;
    };
    
    # Nginx configuration for Vaultwarden
    services.nginx = {
      enable = true;
      
      # Virtual host for Vaultwarden
      virtualHosts.${cfg.domain} = {
        enableACME = true;
        forceSSL = true;
        
        # Security headers
        extraConfig = ''
          # Security headers
          add_header X-Content-Type-Options nosniff;
          add_header X-Frame-Options DENY;
          add_header X-XSS-Protection "1; mode=block";
          add_header Referrer-Policy "strict-origin-when-cross-origin";
          add_header Permissions-Policy "geolocation=(), microphone=(), camera=()";
          
          # Vaultwarden specific headers
          add_header X-Download-Options noopen;
          add_header X-Permitted-Cross-Domain-Policies none;
          add_header X-Robots-Tag "noindex, nofollow";
          
          # Large file uploads
          client_max_body_size 10M;
          
          # Gzip compression
          gzip on;
          gzip_vary on;
          gzip_min_length 1024;
          gzip_proxied expired no-cache no-store private must-revalidate auth;
          gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
        '';
        
        # Locations
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.vaultwarden.port}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # Timeouts
              proxy_connect_timeout 60s;
              proxy_send_timeout 60s;
              proxy_read_timeout 60s;
            '';
          };
          
          "/notifications/hub" = {
            proxyPass = "http://127.0.0.1:${toString cfg.vaultwarden.port}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # WebSocket specific settings
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
            '';
          };
        };
      };
    };
    
    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        80   # HTTP
        443  # HTTPS
        cfg.vaultwarden.port  # Vaultwarden
      ];
    };
    
    # Create Vaultwarden user
    users.users.vaultwarden = {
      isSystemUser = true;
      group = "vaultwarden";
      home = cfg.vaultwarden.dataDir;
      createHome = true;
    };
    
    users.groups.vaultwarden = {};
    
    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.vaultwarden.dataDir} 0755 vaultwarden vaultwarden"
      "d ${cfg.vaultwarden.webVault.path} 0755 vaultwarden vaultwarden"
      "d /var/log/vaultwarden 0755 vaultwarden vaultwarden"
    ];
    
    # Systemd services
    systemd.services = {
      # Vaultwarden service
      "vaultwarden" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        
        serviceConfig = {
          # User and group
          User = "vaultwarden";
          Group = "vaultwarden";
          
          # Working directory
          WorkingDirectory = cfg.vaultwarden.dataDir;
          
          # Environment
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") cfg.services.vaultwarden.config;
          
          # Security settings
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          
          # Capabilities
          AmbientCapabilities = "CAP_NET_BIND_SERVICE";
          CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
          
          # Logging
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
      
      # Nginx service
      "nginx" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
    };
    
    # Health check for Vaultwarden
    systemd.services.vaultwarden-health = {
      description = "Vaultwarden health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "vaultwarden.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.vaultwarden.port}/alive";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
    # Default environment variables
    services.nixmox.vaultwarden.vaultwarden.environment = {
      # Additional security settings
      DISABLE_ICON_DOWNLOAD = "false";
      ICON_CACHE_TTL = "2592000";
      ICON_CACHE_NEGTTL = "259200";
      
      # Database settings
      DATABASE_MAX_CONNS = "10";
      
      # Email settings
      SMTP_TIMEOUT = "15";
      SMTP_ACCEPT_INVALID_HOSTNAMES = "false";
      SMTP_ACCEPT_INVALID_CERTS = "false";
      
      # Security settings
      SHOW_PASSWORD_HINT = "false";
      PASSWORD_HINTS_ALLOWED = "false";
      DISABLE_2FA_REMEMBER = "false";
      
      # Organization settings
      ORG_CREATION_USERS = "admin@${cfg.primaryDomain}";
      
      # Backup settings
      BACKUP_FREQUENCY = "12h";
      BACKUP_ATTEMPTS = "3";
      
      # Logging
      EXTENDED_LOGGING = "true";
      LOG_FILE = "/var/log/vaultwarden/vaultwarden.log";
    };
  };
} 