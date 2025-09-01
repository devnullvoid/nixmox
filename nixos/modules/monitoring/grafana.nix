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
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get all services from manifest
  allServices = (manifest.core_services or {}) // (manifest.services or {});
  
  # Determine effective hostname
  hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${baseDomain}";
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
    # Grafana configuration
    services.grafana = {
      enable = true;

      # Settings
      settings = {
        server = {
          http_port = cfg.port;
          domain = hostNameEffective;
          root_url = "https://${hostNameEffective}/";
          # Listen on loopback only (behind Caddy)
          http_addr = "127.0.0.1";
        };

        security = {
          admin_password = cfg.adminPassword;
        };

        users = {
          allow_sign_up = false;
        };

        # Database configuration (manifest-driven)
        database = {
          type = "postgres";
          host = "${dbConfig.host or "postgresql.nixmox.lan"}:${toString (dbConfig.port or 5432)}";
          name = dbConfig.name or "grafana";
          user = dbConfig.owner or "grafana";
          password = cfg.dbPassword;
          ssl_mode = "disable";
        };

        # Datasources (auto-configured)
        "datasources.datasources.yaml" = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://127.0.0.1:9090";
              access = "proxy";
              isDefault = true;
            }
          ] ++ (lib.optional cfg.loki.enable {
            name = "Loki";
            type = "loki";
            url = "http://127.0.0.1:${toString cfg.loki.port}";
            access = "proxy";
          });
        };
      };

      # Provisioning
      provision = {
        enable = true;
        datasources = {
          settings = {
            apiVersion = 1;
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                url = "http://127.0.0.1:9090";
                access = "proxy";
                isDefault = true;
              }
            ] ++ (lib.optional cfg.loki.enable {
              name = "Loki";
              type = "loki";
              url = "http://127.0.0.1:${toString cfg.loki.port}";
              access = "proxy";
            });
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
