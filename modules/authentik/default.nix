{ config, lib, pkgs, authentik-nix, ... }:

with lib;

let
  cfg = config.services.nixmox.authentik;
in {
  options.services.nixmox.authentik = {
    enable = mkEnableOption "Authentik identity provider";
    
    domain = mkOption {
      type = types.str;
      default = "auth.nixmox.lan";
      description = "Domain for Authentik service";
    };
    
    adminEmail = mkOption {
      type = types.str;
      default = "admin@nixmox.lan";
      description = "Admin email for Authentik";
    };
    
    secretKey = mkOption {
      type = types.str;
      default = "changeme"; # Default secret key, should be overridden via SOPS
      description = "Django secret key for Authentik";
    };
    
    postgresPassword = mkOption {
      type = types.str;
      default = "changeme"; # Default password, should be overridden via SOPS
      description = "PostgreSQL password for Authentik";
    };
    
    redisPassword = mkOption {
      type = types.str;
      default = "changeme"; # Default password, should be overridden via SOPS
      description = "Redis password for Authentik";
    };
    
    adminPassword = mkOption {
      type = types.str;
      default = "changeme"; # Default password, should be overridden via SOPS
      description = "Admin password for Authentik";
    };
  };

  config = mkIf cfg.enable {
    # TODO: Import Authentik from the community flake
    # For now, just enable basic services
    
    # TODO: Authentik service configuration
    # services.authentik = {
    #   enable = true;
    #   # Configuration will be added when authentik-nix is properly integrated
    # };
    
    # PostgreSQL for Authentik
    services.postgresql = {
      enable = true;
      
      # Create database and user
      ensureDatabases = [ "authentik" ];
      ensureUsers = [
        {
          name = "authentik";
          # Optionally set a password here if needed
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
    
    # Redis for Authentik
    services.redis = {
      enable = true;
      
      # Settings
      settings = {
        # Security
        requirepass = cfg.redisPassword;
        
        # Performance
        maxmemory = "256mb";
        maxmemory_policy = "allkeys-lru";
        
        # Persistence
        save = [ "900 1" "300 10" "60 10000" ];
      };
    };
    
    # Firewall rules for Authentik
    networking.firewall = {
      allowedTCPPorts = [
        9000  # Authentik web interface
        9001  # Authentik outpost
      ];
    };
    
    # Systemd services
    systemd.services = {
      # Ensure PostgreSQL starts before Authentik
      "authentik" = {
        after = [ "postgresql.service" "redis.service" ];
        requires = [ "postgresql.service" "redis.service" ];
      };
      
      # PostgreSQL settings
      "postgresql" = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
      };
      
      # Redis settings
      "redis" = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
      };
    };
    
    # Create Authentik admin user on first boot
    systemd.services.authentik-init = {
      description = "Initialize Authentik admin user";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik.service" ];
      requires = [ "authentik.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "${pkgs.writeShellScript "authentik-init" ''
            #!/bin/sh
            set -e
            
            # Wait for Authentik to be ready
            until curl -f http://localhost:9000/api/v3/core/applications/ >/dev/null 2>&1; do
              echo "Waiting for Authentik to be ready..."
              sleep 5
            done
            
            # Create admin user if it doesn't exist
            if ! curl -f http://localhost:9000/api/v3/core/users/ -H "Authorization: Bearer $AUTHENTIK_TOKEN" | grep -q "admin"; then
              echo "Creating Authentik admin user..."
              curl -X POST http://localhost:9000/api/v3/core/users/ \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
                -d '{
                  "username": "admin",
                  "email": "${cfg.adminEmail}",
                  "name": "Admin",
                  "is_active": true,
                  "is_superuser": true,
                  "password": "${cfg.adminPassword}"
                }'
            fi
            
            echo "Authentik initialization complete"
          ''}"
        ];
        Environment = [
          "AUTHENTIK_TOKEN=${cfg.secretKey}"
        ];
      };
    };
    
    # Health check for Authentik
    systemd.services.authentik-health = {
      description = "Authentik health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:9000/health/";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
} 