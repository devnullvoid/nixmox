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
    
    # PostgreSQL exporter for database monitoring (temporarily disabled)
    # services.prometheus.exporters.postgres = {
    #   enable = true;
    #   dataSourceNames = [ "postgresql://media:changeme@postgresql.nixmox.lan:5432/media?sslmode=disable" ];
    # };
    
    # Firewall rules - only open backend ports (Caddy handles external access)
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
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
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

    # Expose Caddy vhosts for monitoring services
    services.nixmox.caddy.services = {
      # Prometheus
      prometheus = {
        domain = "prometheus.${hostNameEffective}";
        backend = "127.0.0.1";
        port = 9090;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Prometheus-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Grafana
      grafana = {
        domain = hostNameEffective;
        backend = "127.0.0.1";
        port = cfg.grafana.port;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Grafana-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Alertmanager
      alertmanager = {
        domain = "alertmanager.${hostNameEffective}";
        backend = "127.0.0.1";
        port = 9093;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Alertmanager-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };
    };
  });
} 