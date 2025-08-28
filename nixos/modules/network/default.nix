{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.network;

  # Get network configuration from manifest
  networkConfig = manifest.network or {};

  # Get all services from manifest for dynamic host mappings
  allServices = (manifest.core_services or {}) // (manifest.services or {});

  # Generate dynamic host mappings from manifest services
  dynamicHostMappings = builtins.mapAttrs (serviceName: serviceConfig:
    {
      hostname = serviceConfig.hostname or "${serviceName}.${networkConfig.domain or "nixmox.lan"}";
      ip = serviceConfig.ip or "127.0.0.1";
    }
  ) allServices;

  # Generate dynamic DNS records from manifest services
  dynamicDnsRecords = builtins.mapAttrs (serviceName: serviceConfig:
    {
      domain = serviceConfig.hostname or "${serviceName}.${networkConfig.domain or "nixmox.lan"}";
      ip = serviceConfig.ip or "127.0.0.1";
    }
  ) allServices;
  
in {
  options.services.nixmox.network = {
    enable = mkEnableOption "NixMox network configuration";
    
    # Network infrastructure (manifest-driven)
    dns_server = mkOption {
      type = types.str;
      default = networkConfig.dns_server or "192.168.99.1";
      description = "Internal DNS server IP address (from manifest network config)";
    };

    gateway = mkOption {
      type = types.str;
      default = networkConfig.gateway or "192.168.99.1";
      description = "Network gateway IP address (from manifest network config)";
    };

    network_cidr = mkOption {
      type = types.str;
      default = networkConfig.network_cidr or "192.168.99.0/24";
      description = "Network CIDR range (from manifest network config)";
    };

    vlan_tag = mkOption {
      type = types.int;
      default = networkConfig.vlan_tag or 99;
      description = "VLAN tag for the network (from manifest network config)";
    };
    
    # Container configurations (manifest-driven)
    containers = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          ip = mkOption {
            type = types.str;
            description = "Container IP address";
          };
          gateway = mkOption {
            type = types.str;
            description = "Container gateway";
          };
          vlan_tag = mkOption {
            type = types.int;
            description = "Container VLAN tag";
          };
        };
      });
      default = networkConfig.containers or {};
      description = "Container network configurations (from manifest network config)";
    };

    # DNS records (manifest-driven)
    dns_records = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          domain = mkOption {
            type = types.str;
            description = "Domain name";
          };
          ip = mkOption {
            type = types.str;
            description = "IP address for domain";
          };
        };
      });
      default = dynamicDnsRecords;
      description = "DNS records for internal resolution (dynamically generated from manifest)";
    };

    # Host mappings (manifest-driven)
    host_mappings = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          hostname = mkOption {
            type = types.str;
            description = "Hostname";
          };
          ip = mkOption {
            type = types.str;
            description = "IP address for hostname";
          };
        };
      });
      default = dynamicHostMappings;
      description = "Hostname to IP mappings (dynamically generated from manifest)";
    };
  };
  
  config = mkIf cfg.enable {
    # This module provides network configuration to other modules
    # No additional configuration needed here
  };
}
