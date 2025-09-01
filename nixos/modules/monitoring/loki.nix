{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring.loki;
in {
  options.services.nixmox.monitoring.loki = {
    enable = mkEnableOption "Loki log aggregation";
    
    port = mkOption {
      type = types.int;
      default = 3100;
      description = "Loki HTTP port";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/loki";
      description = "Loki data directory";
    };
    
    retention = mkOption {
      type = types.str;
      default = "168h"; # 7 days
      description = "Log retention period";
    };
  };

  config = mkIf cfg.enable {
    # Loki configuration
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_port = cfg.port;

        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore.store = "inmemory";
              replication_factor = 1;
            };
            final_sleep = "0s";
          };
          chunk_idle_period = "1h";
          max_chunk_age = "1h";
          chunk_target_size = 1048576;
          chunk_retain_period = "30s";
        };

        schema_config.configs = [{
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];

        storage_config = {
          filesystem.directory = "${cfg.dataDir}/chunks";
          tsdb_shipper = {
            active_index_directory = "${cfg.dataDir}/tsdb-active";
            cache_location = "${cfg.dataDir}/tsdb-cache";
            cache_ttl = "24h";
          };
        };

        compactor = {
          working_directory = "${cfg.dataDir}/compactor";
          compactor_ring.kvstore.store = "inmemory";
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };
      };
    };

    # Firewall rules
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
    };

    # Systemd services
    systemd.services.loki = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 loki loki"
      "d ${cfg.dataDir}/chunks 0755 loki loki"
      "d ${cfg.dataDir}/tsdb-active 0755 loki loki"
      "d ${cfg.dataDir}/tsdb-cache 0755 loki loki"
      "d ${cfg.dataDir}/compactor 0755 loki loki"
    ];

    # Create users and groups
    users.users.loki = {
      isSystemUser = true;
      group = "loki";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.loki = {};
  };
}
