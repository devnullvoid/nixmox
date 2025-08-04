{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.nextcloud;
in {
  options.services.nixmox.nextcloud = {
    enable = mkEnableOption "Nextcloud file sharing platform";
    
    domain = mkOption {
      type = types.str;
      default = "nextcloud.nixmox.lan";
      description = "Domain for Nextcloud service";
    };
    
    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for services";
    };
    
    # Nextcloud configuration
    nextcloud = {
      hostName = mkOption {
        type = types.str;
        default = "nextcloud.nixmox.lan";
        description = "Nextcloud hostname";
      };
      
      port = mkOption {
        type = types.int;
        default = 80;
        description = "Nextcloud web interface port";
      };
      
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/nextcloud";
        description = "Nextcloud data directory";
      };
      
      adminUser = mkOption {
        type = types.str;
        default = "admin";
        description = "Nextcloud admin username";
      };
      
      adminPassword = mkOption {
        type = types.str;
        default = "changeme";
        description = "Nextcloud admin password (should be overridden via SOPS)";
      };
      
      # Database configuration
      database = {
        type = mkOption {
          type = types.enum [ "sqlite" "postgresql" "mysql" ];
          default = "postgresql";
          description = "Database type for Nextcloud";
        };
        
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "Database host";
        };
        
        name = mkOption {
          type = types.str;
          default = "nextcloud";
          description = "Database name";
        };
        
        user = mkOption {
          type = types.str;
          default = "nextcloud";
          description = "Database user";
        };
        
        password = mkOption {
          type = types.str;
          default = "changeme";
          description = "Database password (should be overridden via SOPS)";
        };
      };
      
      # Redis configuration
      redis = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Redis for Nextcloud";
        };
        
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "Redis host";
        };
        
        port = mkOption {
          type = types.int;
          default = 6379;
          description = "Redis port";
        };
        
        password = mkOption {
          type = types.str;
          default = "changeme";
          description = "Redis password (should be overridden via SOPS)";
        };
      };
      
      # Storage configuration
      storage = {
        dataDir = mkOption {
          type = types.str;
          default = "/var/lib/nextcloud/data";
          description = "Nextcloud data storage directory";
        };
        
        appsDir = mkOption {
          type = types.str;
          default = "/var/lib/nextcloud/apps";
          description = "Nextcloud apps directory";
        };
        
        configDir = mkOption {
          type = types.str;
          default = "/var/lib/nextcloud/config";
          description = "Nextcloud config directory";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Nextcloud configuration
    services.nextcloud = {
      enable = true;
      
      # Basic settings
      hostName = cfg.nextcloud.hostName;
      package = pkgs.nextcloud28;
      
      # Database configuration
      database = {
        type = cfg.nextcloud.database.type;
        host = cfg.nextcloud.database.host;
        name = cfg.nextcloud.database.name;
        user = cfg.nextcloud.database.user;
        password = cfg.nextcloud.database.password;
      };
      
      # Redis configuration
      redis = mkIf cfg.nextcloud.redis.enable {
        enable = true;
        host = cfg.nextcloud.redis.host;
        port = cfg.nextcloud.redis.port;
        password = cfg.nextcloud.redis.password;
      };
      
      # Storage configuration
      dataDir = cfg.nextcloud.storage.dataDir;
      appsDir = cfg.nextcloud.storage.appsDir;
      configDir = cfg.nextcloud.storage.configDir;
      
      # Admin user
      adminUser = cfg.nextcloud.adminUser;
      adminPassword = cfg.nextcloud.adminPassword;
      
      # HTTPS settings
      https = true;
      
      # Auto-update
      autoUpdateApps = {
        enable = true;
        startAt = "05:00:00";
      };
      
      # Extra options
      extraOptions = {
        # Performance settings
        "opcache.enable" = true;
        "opcache.enable_cli" = true;
        "opcache.memory_consumption" = 128;
        "opcache.interned_strings_buffer" = 8;
        "opcache.max_accelerated_files" = 4000;
        "opcache.revalidate_freq" = 2;
        "opcache.fast_shutdown" = 1;
        "opcache.enable_file_override" = 1;
        "opcache.validate_timestamps" = 1;
        
        # Security settings
        "session.cookie_secure" = true;
        "session.cookie_httponly" = true;
        "session.cookie_samesite" = "Lax";
        
        # File upload settings
        "upload_max_filesize" = "10G";
        "post_max_size" = "10G";
        "max_execution_time" = 3600;
        "max_input_time" = 3600;
        "memory_limit" = "512M";
        
        # Logging
        "log_type" = "error_log";
        "log_level" = "WARN";
      };
    };
    
    # PostgreSQL for Nextcloud (if using PostgreSQL)
    services.postgresql = mkIf (cfg.nextcloud.database.type == "postgresql") {
      enable = true;
      
      # Create database and user
      ensureDatabases = [ cfg.nextcloud.database.name ];
      ensureUsers = [
        {
          name = cfg.nextcloud.database.user;
          ensurePermissions = {
            "DATABASE ${cfg.nextcloud.database.name}" = "ALL PRIVILEGES";
          };
        }
      ];
      
      # Settings
      settings = {
        # Performance settings
        shared_buffers = "256MB";
        effective_cache_size = "1GB";
        maintenance_work_mem = "64MB";
        checkpoint_completion_target = "0.9";
        wal_buffers = "16MB";
        default_statistics_target = "100";
        random_page_cost = "1.1";
        effective_io_concurrency = "200";
        work_mem = "4MB";
        min_wal_size = "1GB";
        max_wal_size = "4GB";
      };
    };
    
    # Redis for Nextcloud (if enabled)
    services.redis.servers.nextcloud = mkIf cfg.nextcloud.redis.enable {
      enable = true;
      settings = {
        # Security
        requirepass = cfg.nextcloud.redis.password;
        
        # Performance
        maxmemory = "256mb";
        
        # Persistence
        save = [ "900 1" "300 10" "60 10000" ];
      };
    };
    
    # Nginx configuration
    services.nginx = {
      enable = true;
      
      # Virtual host for Nextcloud
      virtualHosts.${cfg.nextcloud.hostName} = {
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
          
          # Nextcloud specific headers
          add_header X-Download-Options noopen;
          add_header X-Permitted-Cross-Domain-Policies none;
          add_header X-Robots-Tag "noindex, nofollow";
          
          # Large file uploads
          client_max_body_size 10G;
          fastcgi_buffers 64 4K;
          
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
            extraConfig = ''
              rewrite ^ /index.php$request_uri;
            '';
          };
          
          "~ ^\\/(?:build|tests|config|lib|3rdparty|templates|data)\\/" = {
            extraConfig = ''
              deny all;
            '';
          };
          
          "~ ^\\/(?:\\.|autotest|occ|issue|indie|db_|console)" = {
            extraConfig = ''
              deny all;
            '';
          };
          
          "~ ^\\/(?:index|remote|public|cron|core/ajax\\/update|status|ocs\\/v[12]|updater\\/.+|oc[ms]-provider\\/.+)\\.php(?:$|\\/)" = {
            extraConfig = ''
              fastcgi_split_path_info ^(.+\\.php)(\\/.*)$;
              set $path_info $fastcgi_path_info;
              fastcgi_param PATH_INFO $path_info;
              fastcgi_param HTTPS on;
              fastcgi_param modHeadersAvailable true;
              fastcgi_param front_controller_active true;
              fastcgi_pass unix:/run/phpfpm/nextcloud.sock;
              fastcgi_intercept_errors on;
              fastcgi_request_buffering off;
              fastcgi_read_timeout 3600;
              fastcgi_send_timeout 3600;
            '';
          };
          
          "~ ^\\/(?:updater|oc[ms]-provider)(?:$|\\/)" = {
            extraConfig = ''
              try_files $uri/ =404;
            '';
          };
          
          "~ .*\\.(?:css|js|woff2?|svg|gif|map|png|html|ttf|ico|jpg|jpeg|bcmap)$" = {
            extraConfig = ''
              try_files $uri /index.php$request_uri;
              add_header Cache-Control "public, immutable";
              access_log off;
            '';
          };
          
          "~ .*\\.(?:png|html|ttf|ico|jpg|jpeg|bcmap)$" = {
            extraConfig = ''
              try_files $uri /index.php$request_uri;
              access_log off;
            '';
          };
          
          "/.well-known/carddav" = {
            extraConfig = ''
              return 301 $scheme://$host/remote.php/dav;
            '';
          };
          
          "/.well-known/caldav" = {
            extraConfig = ''
              return 301 $scheme://$host/remote.php/dav;
            '';
          };
        };
      };
    };
    
    # PHP-FPM for Nextcloud
    services.phpfpm.pools.nextcloud = {
      user = "nextcloud";
      group = "nextcloud";
      
      settings = {
        "listen" = "/run/phpfpm/nextcloud.sock";
        "listen.owner" = "nginx";
        "listen.group" = "nginx";
        "listen.mode" = "0660";
        
        # Process management
        "pm" = "dynamic";
        "pm.max_children" = 120;
        "pm.start_servers" = 12;
        "pm.min_spare_servers" = 6;
        "pm.max_spare_servers" = 18;
        
        # Performance
        "pm.max_requests" = 500;
        "pm.process_idle_timeout" = "10s";
        
        # Security
        "security.limit_extensions" = ".php";
        
        # Environment
        "env[HOSTNAME]" = cfg.nextcloud.hostName;
        "env[PATH]" = "/usr/local/bin:/usr/bin:/bin";
        "env[TMP]" = "/tmp";
        "env[TMPDIR]" = "/tmp";
        "env[TEMP]" = "/tmp";
      };
    };
    
    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        80   # HTTP
        443  # HTTPS
      ];
    };
    
    # Create Nextcloud user
    users.users.nextcloud = {
      isSystemUser = true;
      group = "nextcloud";
      home = cfg.nextcloud.dataDir;
      createHome = true;
    };
    
    users.groups.nextcloud = {};
    
    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.nextcloud.dataDir} 0755 nextcloud nextcloud"
      "d ${cfg.nextcloud.storage.dataDir} 0755 nextcloud nextcloud"
      "d ${cfg.nextcloud.storage.appsDir} 0755 nextcloud nextcloud"
      "d ${cfg.nextcloud.storage.configDir} 0755 nextcloud nextcloud"
      "d /var/log/nextcloud 0755 nextcloud nextcloud"
    ];
    
    # Systemd services
    systemd.services = {
      # Nextcloud service
      "nextcloud-setup" = {
        description = "Nextcloud setup";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.writeShellScript "nextcloud-setup" ''
            #!/bin/sh
            set -e
            
            # Wait for database to be ready
            if [ "${cfg.nextcloud.database.type}" = "postgresql" ]; then
              until pg_isready -h ${cfg.nextcloud.database.host} -U ${cfg.nextcloud.database.user}; do
                echo "Waiting for PostgreSQL..."
                sleep 2
              done
            fi
            
            # Wait for Redis to be ready
            if [ "${toString cfg.nextcloud.redis.enable}" = "true" ]; then
              until redis-cli -h ${cfg.nextcloud.redis.host} -p ${toString cfg.nextcloud.redis.port} -a ${cfg.nextcloud.redis.password} ping; do
                echo "Waiting for Redis..."
                sleep 2
              done
            fi
            
            echo "Nextcloud setup complete"
          ''}";
        };
      };
      
      # Nginx service
      "nginx" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      
      # PHP-FPM service
      "phpfpm-nextcloud" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
    };
    
    # Health check for Nextcloud
    systemd.services.nextcloud-health = {
      description = "Nextcloud health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "nginx.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f https://${cfg.nextcloud.hostName}/status.php";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
} 