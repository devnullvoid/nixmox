{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring;
  
  # Get service configurations from manifest
  serviceConfig = manifest.services.monitoring or {};
  
  # Get proxy configuration from manifest
  proxyConfig = serviceConfig.interface.proxy or {};
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Determine effective hostname
  hostNameEffective = if cfg.hostName != "" then cfg.hostName else "${cfg.subdomain}.${baseDomain}";
in {
  imports = [
    ./prometheus.nix
    ./grafana.nix
    ./alertmanager.nix
    ./loki.nix
    ./promtail.nix
  ];

  options.services.nixmox.monitoring = {
    enable = mkEnableOption "Monitoring stack (Prometheus + Grafana + Loki)";
    
    subdomain = mkOption {
      type = types.str;
      default = "monitoring";
      description = "Subdomain for monitoring services; full host becomes <subdomain>.<services.nixmox.domain>";
    };

    hostName = mkOption {
      type = types.str;
      default = proxyConfig.domain or "monitoring.nixmox.lan";
      description = "Public host name for monitoring services (from manifest proxy config)";
    };

    # Component enablement options are defined in their respective files
    # prometheus = { ... } - defined in prometheus.nix
    # grafana = { ... } - defined in grafana.nix  
    # alertmanager = { ... } - defined in alertmanager.nix
    # loki = { ... } - defined in loki.nix
    # promtail = { ... } - defined in promtail.nix
  };

  config = mkIf cfg.enable {
    # Ensure local resolution works even before DNS is in place
    networking.hosts."127.0.0.1" = [ hostNameEffective ];

    # DEFAULT CONFIGURATION - Start with only Prometheus enabled
    # Uncomment components as you test them:
    
    # Step 1: Start with Prometheus only
    services.nixmox.monitoring.prometheus.enable = true;
    
    # Step 2: Add Grafana when Prometheus is working
    services.nixmox.monitoring.grafana.enable = true;
    
    # Step 3: Add Alertmanager when basic monitoring is working
    services.nixmox.monitoring.alertmanager.enable = true;
    
    # Step 4: Add Loki when monitoring is stable
    services.nixmox.monitoring.loki.enable = true;
    
    # Step 5: Add Promtail when Loki is working
    # services.nixmox.monitoring.promtail.enable = true;
  };
} 