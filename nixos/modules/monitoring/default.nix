{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring;
in {
  options.services.nixmox.monitoring = {
    enable = mkEnableOption "Monitoring stack (Prometheus + Grafana)";
    
    subdomain = mkOption {
      type = types.str;
      default = "monitoring";
      description = "Subdomain for monitoring services; full host becomes <subdomain>.<services.nixmox.domain>";
    };

    hostName = mkOption {
      type = types.str;
      default = "";
      description = "Public host name for monitoring services; defaults to <subdomain>.<services.nixmox.domain>";
    };
    
    # Prometheus configuration
    prometheus = {
      retention = mkOption {
        type = types.str;
        default = "30d";
        description = "Data retention period";
      };
      
      scrapeInterval = mkOption {
        type = types.str;
        default = "15s";
        description = "Scrape interval";
      };
      
      evaluationInterval = mkOption {
        type = types.str;
        default = "15s";
        description = "Evaluation interval";
      };
      
      targets = mkOption {
        type = types.listOf types.str;
        default = [
          "authentik.nixmox.lan:9100"
          "caddy.nixmox.lan:9100"
          "mail.nixmox.lan:9100"
          "media.nixmox.lan:9100"
          "nextcloud.nixmox.lan:9100"
          "vaultwarden.nixmox.lan:9100"
          "dns.nixmox.lan:9100"
          "localhost:9100"
        ];
        description = "Prometheus scrape targets";
      };
      
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/prometheus";
        description = "Prometheus data directory";
      };
      
      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/prometheus";
        description = "Prometheus state directory";
      };
    };
    
    # Grafana configuration
    grafana = {
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
    };
    
    # Alertmanager configuration
    alertmanager = {
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/alertmanager";
        description = "Alertmanager data directory";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${config.services.nixmox.domain}";
    in {
      # Ensure local resolution works even before DNS is in place
      networking.hosts."127.0.0.1" = [ hostNameEffective ];

      # Prometheus configuration
      services.prometheus = {
        enable = true;

        # Global settings
        globalConfig = {
          scrape_interval = cfg.prometheus.scrapeInterval;
          evaluation_interval = cfg.prometheus.evaluationInterval;
        };

        # Scrape configuration
        scrapeConfigs = [
          {
            job_name = "prometheus";
            static_configs = [
              {
                targets = [ "127.0.0.1:9090" ];
                labels = {
                  job = "prometheus";
                };
              }
            ];
          }
          {
            job_name = "postgresql";
            static_configs = [
              {
                targets = [ "postgresql.nixmox.lan:9187" ];
                labels = {
                  job = "postgresql";
                };
              }
            ];
          }
          {
            job_name = "caddy";
            static_configs = [
              {
                targets = [ "localhost:9090" ]; # Caddy exporter
              }
            ];
          }
        ];

        # Retention
        retentionTime = cfg.prometheus.retention;

        # Listen on loopback only (behind Caddy)
        listenAddress = "127.0.0.1";
        port = 9090;
      };

      # Alertmanager configuration
      services.prometheus.alertmanager = {
        enable = true;

        # Listen on loopback only (behind Caddy)
        listenAddress = "127.0.0.1";
        port = 9093;

        # Basic configuration
        configuration = {
          global = {
            smtp_smarthost = "mail.nixmox.lan:587";
            smtp_from = "alertmanager@nixmox.lan";
          };

          route = {
            group_by = [ "alertname" "cluster" "service" ];
            group_wait = "30s";
            group_interval = "5m";
            repeat_interval = "1h";
            receiver = "web.hook";
          };

          receivers = [
            {
              name = "web.hook";
              webhook_configs = [
                {
                  url = "http://127.0.0.1:5001/";
                }
              ];
            }
          ];
        };
      };

      # Grafana configuration
      services.grafana = {
        enable = true;

        # Settings
        settings = {
          server = {
            http_port = cfg.grafana.port;
            domain = hostNameEffective;
            root_url = "https://${hostNameEffective}/";
            # Listen on loopback only (behind Caddy)
            http_addr = "127.0.0.1";
          };

          security = {
            admin_password = cfg.grafana.adminPassword;
          };

          users = {
            allow_sign_up = false;
          };

          # Database configuration
          database = {
            type = "postgres";
            host = "postgresql.nixmox.lan:5432";
            name = "grafana";
            user = "grafana";
            password = cfg.grafana.dbPassword;
            ssl_mode = "disable";
          };
        };

        # Note: Grafana provisioning can be configured manually or via API
        # Datasources and dashboards can be added through the web interface
      };

      # PostgreSQL exporter for database monitoring (temporarily disabled)
      # services.prometheus.exporters.postgres = {
      #   enable = true;
      #   dataSourceNames = [ "postgresql://media:changeme@postgresql.nixmox.lan:5432/media?sslmode=disable" ];
      # };

      # Firewall rules
      networking.firewall = {
        allowedTCPPorts = [
          9090  # Prometheus (backend)
          9093  # Alertmanager (backend)
          3000  # Grafana (backend)
          9187  # PostgreSQL exporter (backend)
        ];
      };

      # Systemd services
      systemd.services = {
        prometheus = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        alertmanager = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        grafana = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };

        "prometheus-postgres-exporter" = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
        };
      };

      # Create directories
      systemd.tmpfiles.rules = [
        # Prometheus directories
        "d ${cfg.prometheus.dataDir} 0755 prometheus prometheus"
        "d ${cfg.prometheus.stateDir} 0755 prometheus prometheus"

        # Alertmanager directories
        "d ${cfg.alertmanager.dataDir} 0755 alertmanager alertmanager"

        # Grafana directories
        "d ${cfg.grafana.dataDir} 0755 grafana grafana"
        "d ${cfg.grafana.logDir} 0755 grafana grafana"
      ];

      # Create users and groups
      users.users = {
        prometheus = {
          isSystemUser = true;
          group = "prometheus";
          home = cfg.prometheus.dataDir;
          createHome = true;
        };

        alertmanager = {
          isSystemUser = true;
          group = "alertmanager";
          home = cfg.alertmanager.dataDir;
          createHome = true;
        };

        grafana = {
          isSystemUser = true;
          group = "grafana";
          home = cfg.grafana.dataDir;
          createHome = true;
        };
      };

      users.groups = {
        prometheus = {};
        alertmanager = {};
        grafana = {};
      };
    });
  } 