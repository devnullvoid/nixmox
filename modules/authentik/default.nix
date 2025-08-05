{ config, lib, pkgs, ... }:

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
  };

  config = mkIf cfg.enable {
    # SOPS secrets for Authentik
    sops.secrets = {
      "authentik/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
      };
      "authentik-ldap/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
      };
      "authentik-radius/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
      };
    };

    # Use the official authentik-nix module
    services.authentik = {
      enable = true;
      
      # Use SOPS environment file for secrets
      environmentFile = config.sops.secrets."authentik/env".path;
      
      # Configure settings
      settings = {
        # Email configuration (optional - can be configured later via UI)
        email = {
          host = "smtp.nixmox.lan";
          port = 587;
          username = "authentik@nixmox.lan";
          use_tls = true;
          use_ssl = false;
          from = "authentik@nixmox.lan";
        };
        
        # Disable startup analytics
        disable_startup_analytics = true;
        
        # Use initials for avatars
        avatars = "initials";
        
        # Error reporting
        error_reporting.enabled = false;
        
        # Bootstrap settings
        bootstrap = {
          email = cfg.adminEmail;
        };
        
        # Host configuration
        authentik.host = cfg.domain;
        
        # Listen configuration
        listen = {
          http = "0.0.0.0:9000";
          https = "0.0.0.0:9443";
        };
        
        # PostgreSQL configuration
        postgresql = {
          host = "127.0.0.1";
          port = 5432;
          user = "authentik";
          name = "authentik";
          password = "authentik123";
        };
        
        # Redis configuration - use default port 6379 from authentik-nix module
        redis = {
          host = "127.0.0.1";
          port = 6379;
        };
      };
    };

    # Authentik LDAP outpost
    services.authentik-ldap = {
      enable = true;
      environmentFile = config.sops.secrets."authentik-ldap/env".path;
    };

    # Authentik RADIUS outpost
    services.authentik-radius = {
      enable = true;
      environmentFile = config.sops.secrets."authentik-radius/env".path;
    };

    # PostgreSQL for Authentik
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "authentik" ];
      ensureUsers = [{
        name = "authentik";
        ensureDBOwnership = true;
      }];
      initialScript = pkgs.writeText "authentik-init.sql" ''
        ALTER USER authentik WITH PASSWORD 'authentik123';
      '';
    };

    # Note: Redis is automatically configured by the authentik-nix module
    # on port 6379, so we don't need to configure it manually

    # Create admin user after Authentik is running
    systemd.services.authentik-admin-setup = {
      description = "Setup Authentik admin user";
      wantedBy = [ "authentik.service" ];
      after = [ "authentik.service" ];
      requires = [ "authentik.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "setup-authentik-admin" ''
          # Wait for Authentik to be ready
          for i in {1..30}; do
            if curl -s http://localhost:9000/if/admin/ > /dev/null 2>&1; then
              break
            fi
            sleep 2
          done
          
          # Create admin user if it doesn't exist
          if ! ak shell -c "from authentik.core.models import User; User.objects.filter(username='admin').exists()" 2>/dev/null | grep -q "True"; then
            ak shell -c "
from authentik.core.models import User, Group
from django.contrib.auth.hashers import make_password

# Create admin user
admin_user = User.objects.create(
    username='admin',
    email='${cfg.adminEmail}',
    password=make_password('admin123'),
    is_active=True,
    type='internal_superuser'
)

# Add to admin group
admin_group = Group.objects.get(name='authentik Admins')
admin_group.users.add(admin_user)

print('Admin user created successfully')
"
          else
            echo "Admin user already exists"
          fi
        '';
        User = "authentik";
        Group = "authentik";
      };
    };
  };
} 