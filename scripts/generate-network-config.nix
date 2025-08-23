# Generate NixOS network configuration from Terraform outputs
# This script reads Terraform outputs and generates a NixOS configuration file
# Usage: nix eval -f scripts/generate-network-config.nix --arg terraformOutputs '{"network_config": {...}}'

{ terraformOutputs }:

let
  network = terraformOutputs.network_config;
  containers = network.containers;
  
  # Generate DNS records for Unbound
  dnsRecords = builtins.mapAttrs (name: container: {
    domain = "${name}.nixmox.lan";
    ip = container.ip;
  }) containers;
  
  # Generate host-to-IP mappings for /etc/hosts
  hostMappings = builtins.mapAttrs (name: container: {
    hostname = "${name}.nixmox.lan";
    ip = container.ip;
  }) containers;
  
  # Generate network configuration for each container
  containerNetworks = builtins.mapAttrs (name: container: {
    inherit (container) ip;
    gateway = network.gateway;
    vlan_tag = network.vlan_tag;
  }) containers;

in {
  # Network infrastructure configuration
  network = {
    inherit (network) dns_server gateway network_cidr vlan_tag;
  };
  
  # Container network configurations
  containers = containerNetworks;
  
  # DNS records for Unbound
  dns_records = dnsRecords;
  
  # Host mappings for /etc/hosts
  host_mappings = hostMappings;
  
  # Network ranges
  ranges = {
    network = network.network_cidr;
    gateway = network.gateway;
    dns = network.dns_server;
  };
}
