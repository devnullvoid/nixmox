{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring.promtail;
in {
  options.services.nixmox.monitoring.promtail = {
    enable = mkEnableOption "Promtail log collection";
    
    port = mkOption {
      type = types.int;
      default = 9080;
      description = "Promtail HTTP port";
    };
    
    lokiUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3100/loki/api/v1/push";
      description = "Loki push URL";
    };
  };

  config = mkIf cfg.enable {
    # Promtail configuration
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = cfg.port;
          grpc_listen_port = 0;
        };

        clients = [{
          url = cfg.lokiUrl;
        }];

        scrape_configs = [{
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
              host = config.networking.hostName;
            };
          };
          relabel_configs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }];
      };
    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
    };

    # Systemd services
    systemd.services.promtail = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
