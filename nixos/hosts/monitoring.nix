{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nixmox.monitoring;
in {
  imports = [
    # Core container configuration
    ../modules/core.nix
    
    # Monitoring service module
    ../modules/monitoring
  ];

  # Host-specific configuration
  networking.hostName = "monitoring";
  
  # Enable common services (SSH, monitoring, etc.)
  services.nixmox.enable = true;
  
  # Enable monitoring services
  services.nixmox.monitoring.enable = true;

  # Use external PostgreSQL for Grafana
  # services.nixmox.monitoring.grafana.database = {
  #   type = "postgresql";
  #   host = "postgresql.nixmox.lan";
  #   port = 5432;
  #   name = "grafana";
  #   user = "grafana";
  #   password = "changeme"; # Should be overridden via SOPS
  # };

  # Firewall rules - only allow backend access since we're behind Caddy
  networking.firewall = {
    allowedTCPPorts = [
      9090  # Prometheus backend (behind Caddy)
      9093  # Alertmanager backend (behind Caddy)
      3000  # Grafana backend (behind Caddy)
      9187  # PostgreSQL exporter (backend)
    ];
  };
}
