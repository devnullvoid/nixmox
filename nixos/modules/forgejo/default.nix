{ inputs ? {}, lib, config, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.forgejo;
  
  # Get service configuration from manifest
  forgejoConfig = (manifest.core_services or {}).forgejo or (manifest.services or {}).forgejo or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get core services from manifest
  coreServices = manifest.core_services or {};
  
  # Generate configuration from manifest
  manifestConfig = {
    # Database configuration
    database = {
      host = forgejoConfig.interface.db.host or coreServices.postgresql.ip or "postgresql.${baseDomain}";
      port = forgejoConfig.interface.db.port or 5432;
      name = forgejoConfig.interface.db.name or "forgejo";
      user = forgejoConfig.interface.db.owner or "forgejo";
      # Password will come from SOPS database_password secret via passwordFile
    };
    
    # OIDC configuration
    oidc = {
      client_id = forgejoConfig.interface.auth.oidc.client_id or "forgejo-oidc";
      client_secret = config.sops.secrets.forgejo_oidc_client_secret.path;
      redirect_uri = (forgejoConfig.interface.auth.oidc.redirect_uris or []) ++ [ "https://git.${baseDomain}/user/oauth2/authentik/callback" ];
      scopes = forgejoConfig.interface.auth.oidc.scopes or [ "openid" "email" "profile" ];
      username_claim = forgejoConfig.interface.auth.oidc.username_claim or "preferred_username";
      groups_claim = forgejoConfig.interface.auth.oidc.groups_claim or "groups";
    };
    
    # Server configuration
    server = {
      domain = forgejoConfig.interface.proxy.domain or "git.${baseDomain}";
      root_url = "https://${forgejoConfig.interface.proxy.domain or "git.${baseDomain}"}/";
      http_addr = "0.0.0.0";
      http_port = 3000;
      app_name = "NixMox Forgejo";
      app_url = "https://${forgejoConfig.interface.proxy.domain or "git.${baseDomain}"}/";
    };
    
    # Repository configuration
    repository = {
      root = "/var/lib/forgejo/repositories";
      script_type = "bash";
      max_creation_limit = 50;
      default_branch = "main";
    };
    
    # Security configuration
    security = {
      install_lock = true;
      secret_key = config.sops.secrets.forgejo_secret_key.path;
      internal_token = config.sops.secrets.forgejo_internal_token.path;
      password_hash_algorithm = "pbkdf2";
      min_password_length = 8;
    };
    
    # Admin user configuration
    admin = {
      username = "admin";
      email = "admin@${baseDomain}";
      password = config.sops.secrets.forgejo_admin_password.path;
    };
  };
in {
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  options.services.nixmox.forgejo = {
    enable = mkEnableOption "Enable Forgejo Git server";
    
    # Database configuration
    database = {
      host = mkOption {
        type = types.str;
        default = manifestConfig.database.host;
        description = "PostgreSQL host";
      };
      
      port = mkOption {
        type = types.int;
        default = manifestConfig.database.port;
        description = "PostgreSQL port";
      };
      
      name = mkOption {
        type = types.str;
        default = manifestConfig.database.name;
        description = "PostgreSQL database name";
      };
      
      user = mkOption {
        type = types.str;
        default = manifestConfig.database.user;
        description = "PostgreSQL username";
      };
      

    };
    
    # OIDC configuration
    oidc = {
      client_id = mkOption {
        type = types.str;
        default = manifestConfig.oidc.client_id;
        description = "OIDC client ID";
      };
      
      client_secret = mkOption {
        type = types.str;
        default = manifestConfig.oidc.client_secret;
        description = "OIDC client secret (should be overridden via SOPS)";
      };
      
      redirect_uri = mkOption {
        type = types.listOf types.str;
        default = manifestConfig.oidc.redirect_uri;
        description = "OIDC redirect URIs";
      };
      
      scopes = mkOption {
        type = types.listOf types.str;
        default = manifestConfig.oidc.scopes;
        description = "OIDC scopes";
      };
      
      username_claim = mkOption {
        type = types.str;
        default = manifestConfig.oidc.username_claim;
        description = "OIDC username claim";
      };
      
      groups_claim = mkOption {
        type = types.str;
        default = manifestConfig.oidc.groups_claim;
        description = "OIDC groups claim";
      };
    };
    
    # Server configuration
    server = {
      domain = mkOption {
        type = types.str;
        default = manifestConfig.server.domain;
        description = "Forgejo server domain";
      };
      
      root_url = mkOption {
        type = types.str;
        default = manifestConfig.server.root_url;
        description = "Forgejo root URL";
      };
      
      http_addr = mkOption {
        type = types.str;
        default = manifestConfig.server.http_addr;
        description = "HTTP bind address";
      };
      
      http_port = mkOption {
        type = types.int;
        default = manifestConfig.server.http_port;
        description = "HTTP port";
      };
      
      app_name = mkOption {
        type = types.str;
        default = manifestConfig.server.app_name;
        description = "Application name";
      };
      
      app_url = mkOption {
        type = types.str;
        default = manifestConfig.server.app_url;
        description = "Application URL";
      };
    };
    
    # Repository configuration
    repository = {
      root = mkOption {
        type = types.str;
        default = manifestConfig.repository.root;
        description = "Repository root directory";
      };
      
      script_type = mkOption {
        type = types.str;
        default = manifestConfig.repository.script_type;
        description = "Repository script type";
      };
      
      max_creation_limit = mkOption {
        type = types.int;
        default = manifestConfig.repository.max_creation_limit;
        description = "Maximum repository creation limit";
      };
      
      default_branch = mkOption {
        type = types.str;
        default = manifestConfig.repository.default_branch;
        description = "Default branch name";
      };
    };
    
    # Security configuration
    security = {
      install_lock = mkOption {
        type = types.bool;
        default = manifestConfig.security.install_lock;
        description = "Enable install lock";
      };
      
      secret_key = mkOption {
        type = types.str;
        default = manifestConfig.security.secret_key;
        description = "Secret key (should be overridden via SOPS)";
      };
      
      internal_token = mkOption {
        type = types.str;
        default = manifestConfig.security.internal_token;
        description = "Internal token (should be overridden via SOPS)";
      };
      
      password_hash_algorithm = mkOption {
        type = types.str;
        default = manifestConfig.security.password_hash_algorithm;
        description = "Password hashing algorithm";
      };
      
      min_password_length = mkOption {
        type = types.int;
        default = manifestConfig.security.min_password_length;
        description = "Minimum password length";
      };
    };
    
    # Admin user configuration
    admin = {
      username = mkOption {
        type = types.str;
        default = manifestConfig.admin.username;
        description = "Admin username";
      };
      
      email = mkOption {
        type = types.str;
        default = manifestConfig.admin.email;
        description = "Admin email";
      };
      
      password = mkOption {
        type = types.str;
        default = manifestConfig.admin.password;
        description = "Admin password (should be overridden via SOPS)";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if forgejoConfig.hostname != "" then forgejoConfig.hostname else "${forgejoConfig.subdomain or "git"}.${baseDomain}";
    in {
    
    # SOPS secrets configuration
    sops.secrets.forgejo_env = {
      sopsFile = ../../../secrets/default.yaml;
      key = "forgejo/env";
      mode = "0400";
    };
    
    # Database password secret (for PostgreSQL module)
    sops.secrets.forgejo_database_password = {
      sopsFile = ../../../secrets/default.yaml;
      key = "forgejo/database_password";
      mode = "0400";
    };
    
    # OIDC client secret
    sops.secrets.forgejo_oidc_client_secret = {
      sopsFile = ../../../secrets/default.yaml;
      key = "forgejo/oidc_client_secret";
      mode = "0440";
      owner = "forgejo";
      group = "forgejo";
    };
    
    # Secret key
    sops.secrets.forgejo_secret_key = {
      sopsFile = ../../../secrets/default.yaml;
      key = "forgejo/secret_key";
      mode = "0400";
    };
    
    # Internal token
    sops.secrets.forgejo_internal_token = {
      sopsFile = ../../../secrets/default.yaml;
      key = "forgejo/internal_token";
      mode = "0400";
    };
    
    # Admin password
    sops.secrets.forgejo_admin_password = {
      sopsFile = ../../../secrets/default.yaml;
      key = "forgejo/admin_password";
      mode = "0400";
    };

    # Forgejo service configuration
    services.forgejo = {
      enable = true;
      
      # Database configuration
      database = {
        type = "postgres";
        host = cfg.database.host;
        port = cfg.database.port;
        name = cfg.database.name;
        user = cfg.database.user;
        passwordFile = config.sops.secrets.forgejo_database_password.path;
        createDatabase = false; # We create it manually
      };
      
      settings = {
        # Database configuration is handled at service level
        
        # Server configuration
        server = {
          DOMAIN = cfg.server.domain;
          ROOT_URL = cfg.server.root_url;
          HTTP_ADDR = cfg.server.http_addr;
          HTTP_PORT = cfg.server.http_port;
          APP_NAME = cfg.server.app_name;
          APP_URL = cfg.server.app_url;
          LANDING_PAGE = "explore";
          ENABLE_GZIP = true;
        };
        
        # Repository configuration
        repository = {
          ROOT = cfg.repository.root;
          SCRIPT_TYPE = cfg.repository.script_type;
          MAX_CREATION_LIMIT = cfg.repository.max_creation_limit;
          DEFAULT_BRANCH = cfg.repository.default_branch;
          DEFAULT_PRIVATE = "last";
          DEFAULT_PUSH_CREATE_PRIVATE = true;
          DEFAULT_PUSH_CREATE_PRIVATE_ORG = true;
          DEFAULT_PUSH_CREATE_PRIVATE_TEAM = true;
        };
        
        # Security configuration
        security = {
          INSTALL_LOCK = cfg.security.install_lock;
          SECRET_KEY = cfg.security.secret_key;
          INTERNAL_TOKEN = cfg.security.internal_token;
          PASSWORD_HASH_ALGO = cfg.security.password_hash_algorithm;
          MIN_PASSWORD_LENGTH = cfg.security.min_password_length;
          REQUIRE_SIGNIN_VIEW = false;
          ENABLE_CAPTCHA = false;
          ENABLE_NOTIFY_MAIL = false;
        };
        
        # # OIDC configuration
        # oauth2 = {
        #   ENABLED = true;
        #   JWT_SECRET = config.sops.secrets.forgejo_jwt_secret.path;
        # };
        

        
        # User configuration
        user = {
          ENABLE_EMAIL_NOTIFICATION = false;
          ENABLE_WEB_NOTIFICATION = false;
          DEFAULT_EMAIL_NOTIFICATIONS = "disabled";
          DEFAULT_WEB_NOTIFICATIONS = "disabled";
        };
        
        # Mail configuration (disabled for now)
        mailer = {
          ENABLED = false;
        };
        
        # Logging configuration
        log = {
          LEVEL = "Info";
          ROOT_PATH = "/var/log/forgejo";
          
          # Logger configuration (new format for Forgejo 1.21+)
          # Router logger - logs route handler operations
          "logger.router.MODE" = "console";
          # XORM logger - logs SQL operations (when LOG_SQL is enabled)
          "logger.xorm.MODE" = "console";
          # Access logger - logs HTTP access requests
          "logger.access.MODE" = "console";
        };
        
        # Cache configuration
        cache = {
          ADAPTER = "memory";
          INTERVAL = 60;
        };
        
        # Session configuration
        session = {
          PROVIDER = "db";
          PROVIDER_CONFIG = "file=/var/lib/forgejo/sessions";
          SAME_SITE = "lax";
        };
        
        # Cron configuration
        cron = {
          ENABLE = true;
          RUN_AT_START = true;
        };
      };
    };
    
    # Additional SOPS secret for JWT
    sops.secrets.forgejo_jwt_secret = {
      sopsFile = ../../../secrets/default.yaml;
      key = "forgejo/jwt_secret";
      mode = "0400";
    };
    
    # Systemd service overrides
    systemd.services.forgejo = {
      after = [ "network.target" "postgresql.service" ];
      wants = [ "postgresql.service" ];
      
      serviceConfig = {
        # Mount SOPS secrets
        BindPaths = [
          "/run/secrets:/run/secrets:ro"
        ];
        
        # Environment variables from SOPS
        EnvironmentFile = [
          config.sops.secrets.forgejo_env.path
        ];
        
        # Additional environment variables
        Environment = [
          "FORGEJO_WORK_DIR=/var/lib/forgejo"
          "FORGEJO_CUSTOM=/var/lib/forgejo/custom"
        ];
        

      };
    };
    
    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d /var/lib/forgejo 0755 forgejo forgejo -"
      "d /var/lib/forgejo/repositories 0755 forgejo forgejo -"
      "d /var/lib/forgejo/custom 0755 forgejo forgejo -"
      "d /var/lib/forgejo/sessions 0755 forgejo forgejo -"
      "d /var/log/forgejo 0755 forgejo forgejo -"
    ];
    
    # Firewall configuration
    networking.firewall = {
      allowedTCPPorts = [ cfg.server.http_port ];
    };
    
    # OIDC setup service
    systemd.services.forgejo-oidc-setup = {
      description = "Configure Forgejo OIDC provider via CLI";
      wantedBy = [ "multi-user.target" ];
      after = [ "forgejo.service" "run-secrets.d.mount" ];
      requires = [ "forgejo.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "forgejo";
        Group = "forgejo";
        WorkingDirectory = "/var/lib/forgejo";
        Environment = [
          "FORGEJO_WORK_DIR=/var/lib/forgejo"
          "FORGEJO_CUSTOM=/var/lib/forgejo/custom"
        ];
        
        ExecStart = pkgs.writeShellScript "setup-oidc.sh" ''
          #!/bin/sh
          set -e
          
          echo "Setting up OIDC provider for Forgejo..."
          
          # Wait for Forgejo to be fully ready
          echo "Waiting for Forgejo to be ready..."
          for i in $(seq 1 30); do
            if /run/current-system/sw/bin/curl -f -s http://localhost:3000/api/v1/version >/dev/null 2>&1; then
              echo "Forgejo is ready"
              break
            fi
            echo "Waiting for Forgejo... (attempt $i/30)"
            sleep 2
          done
          
          # Build auto-discover URL using Nix variables (interpolated at build time)
          AUTO_DISCOVER_URL="https://${forgejoConfig.interface.auth.domain or "auth.${baseDomain}"}/application/o/${forgejoConfig.interface.auth.oidc.app_name or "forgejo"}/.well-known/openid-configuration"
          
          echo "Using auto-discover URL: $AUTO_DISCOVER_URL"
          
          # Read OIDC client secret from SOPS (only once)
          echo "Reading OIDC client secret..."
          CLIENT_SECRET=$(cat ${config.sops.secrets.forgejo_oidc_client_secret.path})
          
          # Check if OIDC provider already exists and get its ID
          echo "Checking existing OIDC providers..."
          AUTH_LIST_OUTPUT=$(${pkgs.forgejo}/bin/gitea admin auth list --config /var/lib/forgejo/custom/conf/app.ini)
          if echo "$AUTH_LIST_OUTPUT" | grep -q "authentik"; then
            echo "OIDC provider 'authentik' already exists, updating configuration..."
            
            # Extract the ID for the authentik provider (first column, handle tabs and spaces)
            AUTH_ID=$(echo "$AUTH_LIST_OUTPUT" | grep "authentik" | sed 's/^\([0-9]*\).*/\1/')
            echo "Found existing provider with ID: $AUTH_ID"
            
            # Update existing OIDC provider
            echo "Updating OIDC provider configuration..."
            ${pkgs.forgejo}/bin/gitea admin auth update-oauth \
              --id="$AUTH_ID" \
              --name=authentik \
              --provider=openidConnect \
              --key=${cfg.oidc.client_id} \
              --secret="$CLIENT_SECRET" \
              --auto-discover-url="$AUTO_DISCOVER_URL" \
              --scopes='openid email profile'
            
            echo "OIDC provider updated successfully"
          else
            echo "OIDC provider 'authentik' does not exist, creating new one..."
            
            # Configure new OIDC provider using the correct CLI syntax
            echo "Configuring new OIDC provider..."
            ${pkgs.forgejo}/bin/gitea admin auth add-oauth \
              --provider=openidConnect \
              --name=authentik \
              --key=${cfg.oidc.client_id} \
              --secret="$CLIENT_SECRET" \
              --auto-discover-url="$AUTO_DISCOVER_URL" \
              --scopes='openid email profile'
            
            echo "OIDC provider setup completed successfully"
          fi
        '';
        
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
    # Health check service
    systemd.services.forgejo-health = {
      description = "Forgejo health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "forgejo.service" "forgejo-oidc-setup.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f -s http://localhost:${toString cfg.server.http_port}/api/v1/version";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  });
}
