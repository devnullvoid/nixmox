{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.network;
  
  # Import the network configuration
  networkConfig = import ../../network-config.nix;
  
in {
  options.services.nixmox.network = {
    enable = mkEnableOption "NixMox network configuration";
    
    # Network infrastructure
    dns_server = mkOption {
      type = types.str;
      default = networkConfig.network.dns_server;
      description = "Internal DNS server IP address";
    };
    
    gateway = mkOption {
      type = types.str;
      default = networkConfig.network.gateway;
      description = "Network gateway IP address";
    };
    
    network_cidr = mkOption {
      type = types.str;
      default = networkConfig.network.network_cidr;
      description = "Network CIDR range";
    };
    
    vlan_tag = mkOption {
      type = types.int;
      default = networkConfig.network.vlan_tag;
      description = "VLAN tag for the network";
    };
    
    # Container configurations
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
      default = networkConfig.containers;
      description = "Container network configurations";
    };
    
    # DNS records
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
      default = networkConfig.dns_records;
      description = "DNS records for internal resolution";
    };
    
    # Host mappings
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
      default = networkConfig.host_mappings;
      description = "Hostname to IP mappings";
    };
  };
  
  config = mkIf cfg.enable {
    # This module provides network configuration to other modules
    # No additional configuration needed here
  };
}
