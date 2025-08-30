# NixMox Generic Host Template
# This template dynamically generates host configuration from the service manifest
# Usage: nixmox-host { serviceName = "postgresql"; manifest = manifest; }

{ serviceName, manifest, ... }:

let
  # Get service configuration from manifest
  serviceConfig = (manifest.core_services or {}).${serviceName} or (manifest.services or {}).${serviceName} or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get service interface configuration
  interface = serviceConfig.interface or {};
  
  # Generate firewall rules based on service interface
  generateFirewallRules = serviceConfig:
    let
      # Default firewall rules
      defaultRules = {
        allowedTCPPorts = [];
        allowedUDPPorts = [];
      };
      
      # Add database port if service has database interface
      dbRules = if interface.db or {} != {} then {
        allowedTCPPorts = [ (interface.db.port or 5432) ];
      } else {};
      
      # Add proxy port if service has proxy interface
      proxyRules = if interface.proxy or {} != {} then {
        allowedTCPPorts = [ (interface.proxy.port or 8080) ];
      } else {};
      
      # Add health check port if specified
      healthRules = if interface.health or {} != {} then {
        allowedTCPPorts = [ (interface.health.port or 8080) ];
      } else {};
      
      # Add ports from manifest ports array
      portsRules = if serviceConfig.ports or [] != [] then {
        allowedTCPPorts = serviceConfig.ports;
      } else {};
      
      # Merge all rules
      mergedRules = defaultRules // dbRules // proxyRules // healthRules // portsRules;
    in
    mergedRules;
  
  # Generate service-specific imports
  generateImports = serviceName:
    let
      # Core imports for all hosts
      coreImports = [
        ../modules/core.nix
      ];
      
      # Service module import (if it exists)
      serviceModule = ../modules/${serviceName};
      
      # Check if service module exists (this will fail gracefully if it doesn't)
      serviceImports = if builtins.pathExists serviceModule then [ serviceModule ] else [];
    in
    coreImports ++ serviceImports;
in
{
  imports = generateImports serviceName;
  
  # Host-specific configuration
  networking.hostName = serviceConfig.hostname or serviceName;
  networking.domain = baseDomain;
  
  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Configure SSH keys from manifest
  services.nixmox.sshKeys = {
    nixmox = network.ssh_keys.nixmox or [];
    root = network.ssh_keys.root or [];
  };
  
  # Enable the specific service
  services.nixmox.${serviceName}.enable = true;
  
  # Dynamic firewall rules
  networking.firewall = generateFirewallRules serviceConfig;
}
