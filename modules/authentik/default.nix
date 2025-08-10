{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.authentik;
  blueprintDir = "/etc/authentik/blueprints";
  renderedBlueprint = "${blueprintDir}/oidc-vaultwarden.yaml";
  templateFile = pkgs.writeText "oidc-vaultwarden.tmpl.yaml" ''
version: 1
metadata:
  name: OIDC for Vaultwarden
  description: Provider and application for Vaultwarden OIDC integration (rendered)

entries:
  - identifier: vw-authentication-flow
    model: authentik_flows.flow
    attrs:
      name: Vaultwarden Login
      slug: vaultwarden-login
      designation: authentication
      title: "Sign in to Vaultwarden"

  - identifier: vw-client
    model: authentik_providers_oauth2.oauth2provider
    attrs:
      name: Vaultwarden OIDC
      client_type: confidential
      client_id: "$OIDC_CLIENT_ID"
      client_secret: "$OIDC_CLIENT_SECRET"
      redirect_uris:
        - "$OIDC_REDIRECT_URI"
      authorization_flow: !KeyOf vw-authentication-flow
      property_mappings:
        - !Find [authentik_providers_oauth2.propertymapping, name, "OAuth2 - OpenID 'sub' Claim"]
        - !Find [authentik_providers_oauth2.propertymapping, name, "OAuth2 - OpenID 'email' Claim"]
        - !Find [authentik_providers_oauth2.propertymapping, name, "OAuth2 - OpenID 'profile' Claim"]
      scopes:
        - openid
        - email
        - profile

  - identifier: vw-application
    model: authentik_core.application
    attrs:
      name: Vaultwarden
      slug: vaultwarden
      group: Apps
      protocol_provider: !KeyOf vw-client
'';
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
    # Create authentik user and group early in the activation process
    users.users.authentik = {
      isSystemUser = true;
      group = "authentik";
      description = "Authentik identity provider service user";
    };
    
    users.groups.authentik = {};

    # SOPS secrets for Authentik - shared environment file for all services
    sops.secrets = {
      "authentik/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        # Stable path for use by systemd units
        path = "/run/secrets/authentik/authentik-env";
        # Trigger restarts when secret changes
        restartUnits = [
          "authentik.service"
          "authentik-ldap.service"
          "authentik-radius.service"
          # "authentik-proxy.service"
        ];
      };
      # Per-app OIDC creds for blueprint rendering (example: Vaultwarden)
      "vaultwarden/oidc" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        path = "/run/secrets/vaultwarden/oidc";
        restartUnits = [ "authentik.service" ];
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
        # bootstrap = {
        #   email = cfg.adminEmail;
        # };
        
        # # Host configuration
        # authentik.host = cfg.domain;
        
        # # Listen configuration
        # listen = {
        #   http = "0.0.0.0:9000";
        #   https = "0.0.0.0:9443";
        # };
        
        # # PostgreSQL configuration
        # postgresql = {
        #   host = "127.0.0.1";
        #   port = 5432;
        #   user = "authentik";
        #   name = "authentik";
        #   password = "authentik123";
        # };
        
        # # Redis configuration - use default port 6379 from authentik-nix module
        # redis = {
        #   host = "127.0.0.1";
        #   port = 6379;
        # };
      };
    };

    # Add blueprints directory for declarative configuration
    services.authentik.settings.blueprints_dir = blueprintDir;

    # Enable outpost services using the same environment file
    services.authentik-ldap = {
      enable = true;
      environmentFile = config.sops.secrets."authentik/env".path;
    };

    services.authentik-radius = {
      enable = true;
      environmentFile = config.sops.secrets."authentik/env".path;
    };

    # Use embedded proxy outpost instead
    # services.authentik-proxy = {
    #   enable = true;
    #   environmentFile = "/run/secrets/authentik/authentik-env";
    # };

    # Copy blueprint files to authentik directory
    systemd.services.authentik-blueprints = {
      description = "Install Authentik blueprints";
      wantedBy = [ "multi-user.target" ];
      before = [ "authentik.service" "authentik-migrate.service" ];
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = [
          config.sops.secrets."authentik/env".path
          config.sops.secrets."vaultwarden/oidc".path
        ];
        ExecStart = pkgs.writeShellScript "install-authentik-blueprints" ''
          set -euo pipefail
          mkdir -p ${blueprintDir}
          # Render OIDC blueprint with static client credentials from sops
          ${pkgs.gettext}/bin/envsubst < ${templateFile} > ${renderedBlueprint}
          # Copy other static blueprints
          cp ${./blueprints}/*.yaml ${blueprintDir}/
          chown -R authentik:authentik ${blueprintDir}
          chmod -R 0755 ${blueprintDir}
        '';
      };
    };

        # Note: We use the embedded outpost that runs within the main authentik server
    # The embedded outpost handles LDAP, RADIUS, and Proxy protocols automatically
    # and is accessible on the same ports as authentik (9000/9443)
    # Paths starting with /outpost.goauthentik.io are automatically routed to the embedded outpost

    # PostgreSQL for Authentik (ensure DB/user and schema ownership)
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "authentik" ];
      ensureUsers = [{
        name = "authentik";
        ensureDBOwnership = true;
      }];
      # Runs on initial cluster/database creation only (no secrets here)
      initialScript = pkgs.writeText "authentik-init.sql" ''
        ALTER SCHEMA public OWNER TO authentik;
      '';
    };

    # Note: Redis is automatically configured by the authentik-nix module
    # on port 6379, so we don't need to configure it manually

    # Set Authentik DB user's password from sops secret at activation time
    systemd.services.postgresql-authentik-password = {
      description = "Set password for PostgreSQL role 'authentik' from sops secret";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "sops-install-secrets.service" ];
      requires = [ "postgresql.service" "sops-install-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        EnvironmentFile = config.sops.secrets."authentik/env".path;
        ExecStart = pkgs.writeShellScript "set-authentik-db-password" ''
          PSQL="${config.services.postgresql.package}/bin/psql"
          # Apply password (idempotent)
          "$PSQL" -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE authentik WITH PASSWORD '$AUTHENTIK_POSTGRESQL__PASSWORD';
SQL
        '';
      };
    };

    # Optional oneshot admin creation can be added if needed; bootstrap should suffice

    # Create admin user after Authentik is running
#     systemd.services.authentik-admin-setup = {
#       description = "Setup Authentik admin user";
#       wantedBy = [ "authentik.service" ];
#       after = [ "authentik.service" ];
#       requires = [ "authentik.service" ];
#       serviceConfig = {
#         Type = "oneshot";
#         RemainAfterExit = true;
#         ExecStart = pkgs.writeShellScript "setup-authentik-admin" ''
#           # Wait for Authentik to be ready
#           for i in {1..30}; do
#             if curl -s http://localhost:9000/if/admin/ > /dev/null 2>&1; then
#               break
#             fi
#             sleep 2
#           done
          
#           # Create admin user if it doesn't exist
#           if ! ak shell -c "from authentik.core.models import User; User.objects.filter(username='admin').exists()" 2>/dev/null | grep -q "True"; then
#             ak shell -c "
# from authentik.core.models import User, Group
# from django.contrib.auth.hashers import make_password

# # Create admin user
# admin_user = User.objects.create(
#     username='admin',
#     email='${cfg.adminEmail}',
#     password=make_password('admin123'),
#     is_active=True,
#     type='internal_superuser'
# )

# # Add to admin group
# admin_group = Group.objects.get(name='authentik Admins')
# admin_group.users.add(admin_user)

# print('Admin user created successfully')
# "
#           else
#             echo "Admin user already exists"
#           fi
#         '';
#         User = "authentik";
#         Group = "authentik";
#       };
  };
}