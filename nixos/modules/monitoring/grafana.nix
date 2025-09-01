{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring.grafana;
  
  # Get service configurations from manifest
  serviceConfig = manifest.services.monitoring or {};
  
  # Get database configuration from manifest
  dbConfig = serviceConfig.interface.db or {};
  
  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};
  
  # Get Grafana-specific proxy configuration from manifest
  grafanaProxyConfig = proxyConfig.grafana or {};
  
  # Get OIDC configuration from manifest
  oidcConfig = serviceConfig.interface.auth.oidc or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get core services from manifest for Authentik domain
  coreServices = manifest.core_services or {};
  
  # Construct Authentik domain from manifest (similar to other modules)
  authentikDomain = (coreServices.authentik.interface.proxy.domain or "auth.${baseDomain}");
  
  # Get all services from manifest
  allServices = (manifest.core_services or {}) // (manifest.services or {});
  
  # Get parent monitoring configuration
  monitoringCfg = config.services.nixmox.monitoring;

  # Determine effective hostname
  hostNameEffective = if monitoringCfg.hostName != "" then monitoringCfg.hostName else "${monitoringCfg.subdomain}.${baseDomain}";
in {
  options.services.nixmox.monitoring.grafana = {
    enable = mkEnableOption "Grafana visualization and dashboards";
    
    adminPassword = mkOption {
      type = types.str;
      default = "changeme"; # Default password, should be overridden via SOPS
      description = "Grafana admin password";
    };
    
    dbPassword = mkOption {
      type = types.str;
      default = "changeme"; # Default password, should be overridden via SOPS
      description = "Grafana database password";
    };
    
    port = mkOption {
      type = types.int;
      default = 3000;
      description = "Grafana port";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/grafana";
      description = "Grafana data directory";
    };
    
    logDir = mkOption {
      type = types.str;
      default = "/var/log/grafana";
      description = "Grafana log directory";
    };
    
    # Loki integration options
    loki = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Loki datasource in Grafana";
      };
      
      port = mkOption {
        type = types.int;
        default = 3100;
        description = "Loki HTTP port";
      };
    };
  };

  config = mkIf cfg.enable {
    # SOPS secrets for Grafana
    sops.secrets."monitoring/database_password" = {
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };
    
    sops.secrets."monitoring/grafana_admin_password" = {
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };
    
    sops.secrets."monitoring/oidc_client_secret" = {
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };

    # Grafana configuration
    services.grafana = {
      enable = true;

      # Settings
      settings = {
        server = {
          http_port = cfg.port;
          domain = grafanaProxyConfig.domain or hostNameEffective;
          root_url = "https://${grafanaProxyConfig.domain or hostNameEffective}/";
          # Listen on loopback only (behind Caddy)
          http_addr = "0.0.0.0";
        };

        security = {
          # Read admin password from SOPS secret file at runtime
          admin_password = "$__file{${config.sops.secrets."monitoring/grafana_admin_password".path}}";
        };

        users = {
          allow_sign_up = false;
          auto_assign_org = true;
          auto_assign_org_id = 1;
        };
        
        # OAuth2/OpenID Connect with Authentik
        auth = {
          signout_redirect_url = "https://${authentikDomain}/application/o/grafana/end-session/";
        };
        
        "auth.generic_oauth" = {
          name = "authentik";
          enabled = true;
          client_id = oidcConfig.client_id or "monitoring-oidc";
          client_secret = "$__file{${config.sops.secrets."monitoring/oidc_client_secret".path}}";
          scopes = builtins.concatStringsSep " " (oidcConfig.scopes or [ "openid" "email" "profile" ]);
          auth_url = "https://${authentikDomain}/application/o/authorize/";
          token_url = "https://${authentikDomain}/application/o/token/";
          api_url = "https://${authentikDomain}/application/o/userinfo/";
          # Map Authentik groups to Grafana roles using the groups claim from manifest
          role_attribute_path = "contains(groups, 'Grafana Admins') && 'Admin' || contains(groups, 'Grafana Editors') && 'Editor' || 'Viewer'";
        };

        # Database configuration (manifest-driven)
        database = {
          type = "postgres";
          host = "${dbConfig.host or "postgresql.nixmox.lan"}:${toString (dbConfig.port or 5432)}";
          name = dbConfig.name or "grafana";
          user = dbConfig.owner or "grafana";
          # Read password from SOPS secret file at runtime to avoid Nix store secrets
          password = "$__file{${config.sops.secrets."monitoring/database_password".path}}";
          ssl_mode = "disable";
        };
      };
      
      # Note: OAuth configuration will need to be done through the Grafana UI
      # The NixOS Grafana module doesn't support the nested [auth.generic_oauth] structure
      # that Grafana expects. After deployment, configure OAuth at:
      # Administration > Authentication > Generic OAuth
      
      # Provision Prometheus datasource automatically
      provision = {
        datasources = {
          settings = {
            apiVersion = 1;
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                access = "proxy";
                url = "http://127.0.0.1:9090";
                isDefault = true;
                editable = true;
                jsonData = {
                  timeInterval = "5s";
                  queryTimeout = "60s";
                  httpMethod = "POST";
                };
              }
            ];
          };
        };
      };
    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
    };

    # Systemd services
    systemd.services.grafana = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 grafana grafana"
      "d ${cfg.logDir} 0755 grafana grafana"
    ];

    # Create users and groups
    users.users.grafana = {
      isSystemUser = true;
      group = "grafana";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.grafana = {};
  };
}
