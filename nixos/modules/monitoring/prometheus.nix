{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring.prometheus;
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get all services from manifest for dynamic target generation
  allServices = (manifest.core_services or {}) // (manifest.services or {});

  # Generate dynamic Prometheus targets from manifest
  # All services get Node Exporters via the common module
  prometheusTargets = builtins.mapAttrs (serviceName: serviceConfig:
    let
      hostname = serviceConfig.hostname or "${serviceName}.${baseDomain}";
    in
    "${hostname}:9100"
  ) allServices;

  # Convert to list format
  prometheusTargetsList = builtins.attrValues prometheusTargets ++ ["localhost:9100"];
in {
  options.services.nixmox.monitoring.prometheus = {
    enable = mkEnableOption "Prometheus metrics collection and alerting";
    
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

  config = mkIf cfg.enable {
    # Prometheus configuration
    services.prometheus = {
      enable = true;

      # Global settings
      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = cfg.evaluationInterval;
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
          job_name = "node";
          static_configs = builtins.map (target: {
            targets = [ target ];
            labels = {
              job = "node";
            };
          }) cfg.targets;
        }
        # PostgreSQL exporter (runs on postgresql.nixmox.lan)
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
        # Caddy exporter (runs on caddy.nixmox.lan)
        {
          job_name = "caddy";
          static_configs = [
            {
              targets = [
                "${allServices.caddy.hostname or "caddy.nixmox.lan"}:2019"
              ];
              labels = {
                job = "caddy";
              };
            }
          ];
        }
      ];

      # Retention
      retentionTime = cfg.retention;

      # Listen on all interfaces so Caddy can reach us
      listenAddress = "0.0.0.0";
      port = 9090;
    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [ 9090 ];
    };

    # Systemd services
    systemd.services.prometheus = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 prometheus prometheus"
      "d ${cfg.stateDir} 0755 prometheus prometheus"
    ];

    # Create users and groups
    users.users.prometheus = {
      isSystemUser = true;
      group = "prometheus";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.prometheus = {};
  };
}
