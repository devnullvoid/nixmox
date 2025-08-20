{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring;
in {
  options.services.nixmox.monitoring = {
    enable = mkEnableOption "Monitoring stack (Prometheus + Grafana)";
    
    domain = mkOption {
      type = types.str;
      default = "monitoring.nixmox.lan";
      description = "Domain for monitoring services";
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
    };
    
    # Grafana configuration
    grafana = {
      adminPassword = mkOption {
        type = types.str;
        default = "changeme"; # Default password, should be overridden via SOPS
        description = "Grafana admin password";
      };
      
      port = mkOption {
        type = types.int;
        default = 3000;
        description = "Grafana port";
      };
    };
  };

  config = mkIf cfg.enable {
    # Prometheus configuration
    services.prometheus = {
      enable = true;
      
      # Global settings
      globalConfig = {
        scrape_interval = cfg.prometheus.scrapeInterval;
        evaluation_interval = "15s";
      };
      
      # Scrape configurations
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = cfg.prometheus.targets;
              labels = {
                job = "node";
              };
            }
          ];
        }
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "localhost:9090" ];
              labels = {
                job = "prometheus";
              };
            }
          ];
        }
        {
          job_name = "caddy";
          static_configs = [
            {
              targets = [ "localhost:2019" ];
              labels = {
                job = "caddy";
              };
            }
          ];
          metrics_path = "/metrics";
        }
        {
          job_name = "postgresql";
          static_configs = [
            {
              targets = [ "localhost:9187" ];
              labels = {
                job = "postgresql";
              };
            }
          ];
        }
      ];
      
      # Alertmanager configuration
      alertmanager = {
        enable = true;
        configuration = {
          global = {
            smtp_smarthost = "mail.nixmox.lan:587";
            smtp_from = "alertmanager@nixmox.lan";
          };
          
          route = {
            group_by = [ "alertname" ];
            group_wait = "10s";
            group_interval = "10s";
            repeat_interval = "1h";
            receiver = "admin";
          };
          
          receivers = [
            {
              name = "admin";
              email_configs = [
                {
                  to = "admin@nixmox.lan";
                }
              ];
            }
          ];
        };
      };
      
      # Simplified alert rules - using string format instead of complex nested structure
      rules = [
        ''
          groups:
          - name: nixmox
            rules:
            - alert: HighCPUUsage
              expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "High CPU usage on {{ $labels.instance }}"
                description: "CPU usage is above 80% for 5 minutes"
            
            - alert: HighMemoryUsage
              expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "High memory usage on {{ $labels.instance }}"
                description: "Memory usage is above 85% for 5 minutes"
            
            - alert: HighDiskUsage
              expr: (node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100 > 85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "High disk usage on {{ $labels.instance }}"
                description: "Disk usage is above 85% for 5 minutes"
            
            - alert: ServiceDown
              expr: up == 0
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "Service down on {{ $labels.instance }}"
                description: "Service {{ $labels.job }} is down on {{ $labels.instance }}"
        ''
      ];
      
      # Retention
      retentionTime = cfg.prometheus.retention;
    };
    
    # Grafana configuration
    services.grafana = {
      enable = true;
      
      # Settings
      settings = {
        server = {
          http_port = cfg.grafana.port;
          domain = cfg.domain;
          root_url = "https://${cfg.domain}/";
        };
        
        security = {
          admin_password = cfg.grafana.adminPassword;
        };
        
        database = {
          type = "sqlite3";
          path = "/var/lib/grafana/grafana.db";
        };
        
        users = {
          allow_sign_up = false;
        };
        
        # Email settings
        smtp = {
          enabled = true;
          host = "mail.nixmox.lan:587";
          from_address = "grafana@nixmox.lan";
          from_name = "Grafana";
        };
      };
      
      # Note: Grafana provisioning can be configured manually or via API
      # Datasources and dashboards can be added through the web interface
    };
    
    # PostgreSQL exporter for database monitoring (only if Authentik is enabled)
    services.prometheus.exporters.postgres = mkIf (config.services.nixmox ? authentik && config.services.nixmox.authentik.enable) {
      enable = true;
      dataSourceNames = [ "postgresql://authentik:${config.services.nixmox.authentik.postgresPassword}@localhost:5432/authentik?sslmode=disable" ];
    };
    
    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        9090  # Prometheus
        9093  # Alertmanager
        3000  # Grafana
        9187  # PostgreSQL exporter
      ];
    };
    
    # Systemd services
    systemd.services = {
      # Ensure proper startup order
      "prometheus" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      
      "alertmanager" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      
      "grafana" = {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      
      "prometheus-postgres-exporter" = {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
      };
    };
    
    # Create directories
    systemd.tmpfiles.rules = [
      "d /var/lib/grafana 0755 grafana grafana"
      "d /var/lib/prometheus 0755 prometheus prometheus"
      "d /var/lib/alertmanager 0755 alertmanager alertmanager"
    ];
    
    # Health checks
    systemd.services.prometheus-health = {
      description = "Prometheus health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "prometheus.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:9090/-/healthy";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
    systemd.services.grafana-health = {
      description = "Grafana health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "grafana.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.grafana.port}/api/health";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
} 