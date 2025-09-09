{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring.alertmanager;
  
  # Get all services from manifest
  allServices = (manifest.core_services or {}) // (manifest.services or {});
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
in {
  options.services.nixmox.monitoring.alertmanager = {
    enable = mkEnableOption "Alertmanager for alert routing";
    
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/alertmanager";
      description = "Alertmanager data directory";
    };
    
    port = mkOption {
      type = types.int;
      default = 9093;
      description = "Alertmanager HTTP port";
    };
  };

  config = mkIf cfg.enable {
    # Alertmanager configuration
    services.prometheus.alertmanager = {
      enable = true;

      # Listen on all interfaces (behind Caddy)
      listenAddress = "0.0.0.0";
      port = cfg.port;

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

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
    };

    # Systemd services
    systemd.services.alertmanager = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 alertmanager alertmanager"
    ];

    # Create users and groups
    users.users.alertmanager = {
      isSystemUser = true;
      group = "alertmanager";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.alertmanager = {};
  };
}
