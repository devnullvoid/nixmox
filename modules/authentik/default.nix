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
  - id: vw-authentication-flow
    model: authentik_flows.flow
    identifiers:
      slug: vaultwarden-login
    attrs:
      name: Vaultwarden Login
      slug: vaultwarden-login
      designation: authentication
      title: "Sign in to Vaultwarden"

  - id: vw-client
    model: authentik_providers_oauth2.oauth2provider
    identifiers:
      name: Vaultwarden OIDC
    attrs:
      name: Vaultwarden OIDC
      client_type: confidential
      client_id: "$OIDC_CLIENT_ID"
      client_secret: "$OIDC_CLIENT_SECRET"
      redirect_uris: "$OIDC_REDIRECT_URI"
      authentication_flow: !Find [authentik_flows.flow, [slug, "default-authentication-flow"]]
      authorization_flow: !Find [authentik_flows.flow, [slug, "default-provider-authorization-implicit-consent"]]
      

  - id: vw-application
    model: authentik_core.application
    identifiers:
      slug: vaultwarden
    attrs:
      name: Vaultwarden
      slug: vaultwarden
      group: Apps
      provider: !KeyOf vw-client
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
        # Trigger restarts when secret changes
        restartUnits = [
          "authentik.service"
          "authentik-ldap.service"
          "authentik-radius.service"
          # "authentik-proxy.service"
        ];
      };
      "authentik-ldap/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        path = "/run/secrets/authentik-ldap/env";
        restartUnits = [ "authentik-ldap.service" ];
      };
      "authentik-radius/env" = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        path = "/run/secrets/authentik-radius/env";
        restartUnits = [ "authentik-radius.service" ];
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
      environmentFile = "/run/secrets/authentik/env";
      
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
        
        # Bootstrap settings to ensure default flows and initial objects exist
        bootstrap = {
          email = cfg.adminEmail;
        };
        
        # Host configuration for correct redirects/cookies behind proxy
        authentik.host = cfg.domain;
        
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

    # Ensure blueprints run before authentik/migrate by explicitly wanting the unit
    systemd.services.authentik.wants = [ "authentik-blueprints.service" ];
    systemd.services.authentik-migrate.wants = [ "authentik-blueprints.service" ];

    # Add blueprints directory for declarative configuration
    services.authentik.settings.blueprints_dir = blueprintDir;

    # Ship static blueprints declaratively (no runtime copy service needed)
    environment.etc."authentik/blueprints/default-auth-flow.yaml".source = ./blueprints/default-auth-flow.yaml;
    environment.etc."authentik/blueprints/ldap-outpost.yaml".source = ./blueprints/ldap-outpost.yaml;
    environment.etc."authentik/blueprints/radius-outpost.yaml".source = ./blueprints/radius-outpost.yaml;
    environment.etc."authentik/blueprints/proxy-outpost.yaml".source = ./blueprints/proxy-outpost.yaml;

    # Enable outpost services using the same environment file
    # Disable external outposts by default for clean bootstrap; can be enabled later when tokens are set
    services.authentik-ldap = {
      enable = false;
      environmentFile = "/run/secrets/authentik-ldap/env";
    };

    services.authentik-radius = {
      enable = false;
      environmentFile = "/run/secrets/authentik-radius/env";
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
      # Ensure decrypted env files are installed before rendering
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = [ "/run/secrets/authentik/env" "/run/secrets/vaultwarden/oidc" ];
        ExecStart = pkgs.writeShellScript "install-authentik-blueprints" ''
          set -euo pipefail
          mkdir -p ${blueprintDir}
          # Render dynamic OIDC blueprint with client credentials from sops
          ${pkgs.gettext}/bin/envsubst < ${templateFile} > ${renderedBlueprint}
          chown authentik:authentik ${renderedBlueprint} || true
          chmod 0644 ${renderedBlueprint} || true
        '';
      };
    };

    # Ensure default flows and admin user exist post-start
    systemd.services.authentik-ensure-defaults = {
      description = "Ensure Authentik default flows and admin user exist";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik.service" "authentik-migrate.service" ];
      requires = [ "authentik.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = config.sops.secrets."authentik/env".path;
        ExecStart = pkgs.writeShellScript "authentik-ensure-defaults" ''
          set -euo pipefail
          AK=/run/current-system/sw/bin/ak
          if [ ! -x "$AK" ]; then
            echo "ak binary not found at $AK" >&2
            exit 127
          fi
          # Wait for ak shell to be usable
          for i in $(seq 1 30); do
            if "$AK" shell -c 'print("ready")' >/dev/null 2>&1; then
              break
            fi
            sleep 2
          done

          "$AK" shell -c - <<'PY'
from django.contrib.auth import get_user_model
from authentik.core.models import Group
from authentik.flows.models import Flow, FlowDesignation, FlowStageBinding
from authentik.stages.identification.models import IdentificationStage
from authentik.stages.password.models import PasswordStage
from authentik.stages.user_login.models import UserLoginStage
import os

# Default Authentication flow
flow, _ = Flow.objects.get_or_create(
    slug="default-authentication-flow",
    defaults={"name": "Default Authentication", "designation": FlowDesignation.AUTHENTICATION, "title": "Sign in"},
)

id_stage, _ = IdentificationStage.objects.get_or_create(
    name="Default Identification",
    defaults={"user_fields": ["email", "username"]},
)

pw_stage = PasswordStage.objects.filter(name="Default Password").first()
if not pw_stage:
    pw_stage = PasswordStage.objects.create(
        name="Default Password",
        backends=["authentik.core.auth.InbuiltBackend"],
    )
elif not pw_stage.backends:
    pw_stage.backends = ["authentik.core.auth.InbuiltBackend"]
    pw_stage.save()

login_stage, _ = UserLoginStage.objects.get_or_create(name="Default User Login")

# Rebind stages in correct order
FlowStageBinding.objects.filter(target=flow).delete()
FlowStageBinding.objects.create(target=flow, stage=id_stage, order=0)
FlowStageBinding.objects.create(target=flow, stage=pw_stage, order=1)
FlowStageBinding.objects.create(target=flow, stage=login_stage, order=2)

# Ensure admin user exists and has access
User = get_user_model()
admin_user, _ = User.objects.get_or_create(
    username="akadmin",
    defaults={"email": "${cfg.adminEmail}", "is_active": True, "type": "internal_superuser"},
)
admin_user.is_active = True
admin_user.is_superuser = True
pw = os.environ.get("AUTHENTIK_BOOTSTRAP_PASSWORD") or os.environ.get("AKADMIN_PASSWORD") or "admin123"
admin_user.set_password(pw)
admin_user.save()

group, _ = Group.objects.get_or_create(name="authentik Admins")
group.users.add(admin_user)

print("defaults ensured")
PY

          # Ensure admin group and permissions are created and user is added
          # This uses the built-in management command which assigns correct RBAC
          "$AK" create_admin_group akadmin || true
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