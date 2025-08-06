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
              "authentik-proxy/env" = {
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

    # Add blueprints directory for declarative configuration
    services.authentik.settings.blueprints_dir = "/etc/authentik/blueprints";

    # Copy blueprint files to authentik directory
    systemd.services.authentik-blueprints = {
      description = "Copy Authentik blueprints";
      wantedBy = [ "multi-user.target" ];
      before = [ "authentik.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "copy-blueprints" ''
          mkdir -p /etc/authentik/blueprints
          cp ${./blueprints}/*.yaml /etc/authentik/blueprints/
          chown -R authentik:authentik /etc/authentik/blueprints
          chmod -R 755 /etc/authentik/blueprints
        '';
      };
    };

    # Setup outpost tokens after authentik starts
    systemd.services.authentik-outpost-setup = {
      description = "Setup Authentik outpost tokens";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik.service" ];
      wants = [ "authentik.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStart = pkgs.writeShellScript "setup-outpost-tokens" ''
          # Wait for authentik to be ready
          echo "Waiting for Authentik to be ready..."
          until curl -f -s http://localhost:9000/if/admin/ > /dev/null 2>&1; do
            sleep 5
          done
          echo "Authentik is ready!"
          
          # Extract tokens from outposts created by blueprints
          echo "Extracting outpost tokens..."
          export LDAP_TOKEN=$(ak shell -c "from authentik.outposts.models import Outpost; print(Outpost.objects.get(name='LDAP Outpost').token.key, end='')")
          export RADIUS_TOKEN=$(ak shell -c "from authentik.outposts.models import Outpost; print(Outpost.objects.get(name='RADIUS Outpost').token.key, end='')")  
          export PROXY_TOKEN=$(ak shell -c "from authentik.outposts.models import Outpost; print(Outpost.objects.get(name='Proxy Outpost').token.key, end='')")
          
          echo "Creating outpost environment files with real tokens..."
          
          # Create environment files with real tokens
          cat > /tmp/authentik-ldap.env << EOF
          AUTHENTIK_HOST=http://127.0.0.1:9000
          AUTHENTIK_TOKEN=$LDAP_TOKEN
          AUTHENTIK_INSECURE=true
          EOF
          
          cat > /tmp/authentik-radius.env << EOF
          AUTHENTIK_HOST=http://127.0.0.1:9000
          AUTHENTIK_TOKEN=$RADIUS_TOKEN
          AUTHENTIK_INSECURE=true
          EOF
          
          cat > /tmp/authentik-proxy.env << EOF
          AUTHENTIK_HOST=http://127.0.0.1:9000
          AUTHENTIK_TOKEN=$PROXY_TOKEN
          AUTHENTIK_INSECURE=true
          EOF
          
          # Replace the SOPS-managed environment files
          cp /tmp/authentik-ldap.env ${config.sops.secrets."authentik-ldap/env".path}
          cp /tmp/authentik-radius.env ${config.sops.secrets."authentik-radius/env".path}
          cp /tmp/authentik-proxy.env ${config.sops.secrets."authentik-proxy/env".path}
          
          # Set correct permissions
          chown authentik:authentik ${config.sops.secrets."authentik-ldap/env".path}
          chown authentik:authentik ${config.sops.secrets."authentik-radius/env".path}
          chown authentik:authentik ${config.sops.secrets."authentik-proxy/env".path}
          chmod 400 ${config.sops.secrets."authentik-ldap/env".path}
          chmod 400 ${config.sops.secrets."authentik-radius/env".path}
          chmod 400 ${config.sops.secrets."authentik-proxy/env".path}
          
          # Clean up temp files
          rm -f /tmp/authentik-*.env
          
          echo "Outpost tokens configured successfully!"
          echo "LDAP Token: $LDAP_TOKEN"
          echo "RADIUS Token: $RADIUS_TOKEN" 
          echo "PROXY Token: $PROXY_TOKEN"
        '';
      };
    };

    # Authentik outpost services (using authentik-nix module with SOPS environment files)
    services.authentik-ldap = {
      enable = true;
      environmentFile = config.sops.secrets."authentik-ldap/env".path;
    };

    services.authentik-radius = {
      enable = true;
      environmentFile = config.sops.secrets."authentik-radius/env".path;
    };

    services.authentik-proxy = {
      enable = true;
      environmentFile = config.sops.secrets."authentik-proxy/env".path;
    };

    # Ensure outpost services start after token setup
    systemd.services.authentik-ldap.after = [ "authentik-outpost-setup.service" ];
    systemd.services.authentik-ldap.wants = [ "authentik-outpost-setup.service" ];
    
    systemd.services.authentik-radius.after = [ "authentik-outpost-setup.service" ];
    systemd.services.authentik-radius.wants = [ "authentik-outpost-setup.service" ];
    
    systemd.services.authentik-proxy.after = [ "authentik-outpost-setup.service" ];
    systemd.services.authentik-proxy.wants = [ "authentik-outpost-setup.service" ];

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