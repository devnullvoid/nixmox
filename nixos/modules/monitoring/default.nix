{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring;

  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";

  # Get service configurations from manifest
  serviceConfig = manifest.services.monitoring or {};

  # Get database configuration from manifest
  dbConfig = serviceConfig.interface.db or {};

  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};

  # Get all services from manifest for dynamic target generation
  allServices = (manifest.core_services or {}) // (manifest.services or {});

  # Generate dynamic Prometheus targets from manifest
  prometheusTargets = builtins.mapAttrs (serviceName: serviceConfig:
    let
      hostname = serviceConfig.hostname or "${serviceName}.${baseDomain}";
    in
    "${hostname}:9100"
  ) (lib.filterAttrs (name: config:
    # Include services that typically have node exporters
    builtins.elem name [
      "authentik" "caddy" "dns" "mail" "media" "nextcloud" "vaultwarden"
      "guacamole" "monitoring" "postgresql"
    ]
  ) allServices);

  # Convert to list format
  prometheusTargetsList = builtins.attrValues prometheusTargets ++ ["localhost:9100"];
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
      default = proxyConfig.domain or "${cfg.subdomain}.${baseDomain}";
      description = "Public host name for monitoring services (from manifest proxy config)";
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
        default = prometheusTargetsList;
        description = "Prometheus scrape targets (dynamically generated from manifest)";
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

        # Scrape configuration (manifest-driven)
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
                targets = [
                  "${allServices.postgresql.hostname or "postgresql.nixmox.lan"}:9187"
                ];
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
                targets = [
                  "${allServices.caddy.hostname or "caddy.nixmox.lan"}:9090"
                ];
                labels = {
                  job = "caddy";
                };
              }
            ];
          }
          {
            job_name = "node";
            static_configs = builtins.map (target: {
              targets = [ target ];
              labels = {
                job = "node";
              };
            }) cfg.prometheus.targets;
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

        # Basic configuration (manifest-driven)
        configuration = {
          global = {
            smtp_smarthost = "${allServices.mail.hostname or "mail.nixmox.lan"}:587";
            smtp_from = "alertmanager@${baseDomain}";
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

          # Database configuration (manifest-driven)
          database = {
            type = "postgres";
            host = "${dbConfig.host or "postgresql.nixmox.lan"}:${toString (dbConfig.port or 5432)}";
            name = dbConfig.name or "grafana";
            user = dbConfig.owner or "grafana";
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