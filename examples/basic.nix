# Basic NixMox service manifest example
# This shows how to define a simple service configuration

{ config, lib, ... }:

{
  # Enable NixMox services
  services.nixmox = {
    enable = true;
    
    # Network configuration
    network = {
      dns_server = "192.168.99.13";
      gateway = "192.168.99.1";
      network_cidr = "192.168.99.0/24";
      vlan_tag = 99;
    };
    
    # Service definitions
    services = {
      # Infrastructure services
      postgresql = {
        enable = true;
        ip = "192.168.99.11";
        hostname = "postgresql.nixmox.lan";
        depends_on = [];
        health_check = "systemctl is-active --quiet postgresql";
        restart_policy = "unless-stopped";
        resources = {
          memory = "2GB";
          cpu = "2 cores";
          storage = "20GB";
        };
        ports = [5432];
        volumes = ["/var/lib/postgresql:/var/lib/postgresql"];
      };
      
      caddy = {
        enable = true;
        ip = "192.168.99.10";
        hostname = "caddy.nixmox.lan";
        depends_on = [];
        health_check = "curl -f -s http://localhost:2019/health";
        restart_policy = "unless-stopped";
        resources = {
          memory = "1GB";
          cpu = "1 core";
          storage = "5GB";
        };
        ports = [80, 443, 2019];
      };
      
      # Identity service
      authentik = {
        enable = true;
        ip = "192.168.99.12";
        hostname = "authentik.nixmox.lan";
        depends_on = ["postgresql", "caddy"];
        health_check = "curl -f -s http://localhost:9000/health";
        restart_policy = "unless-stopped";
        resources = {
          memory = "2GB";
          cpu = "2 cores";
          storage = "10GB";
        };
        ports = [9000];
        environment = {
          AUTHENTIK_SECRET_KEY = "your-secret-key-here";
          AUTHENTIK_POSTGRESQL__HOST = "postgresql.nixmox.lan";
        };
      };
      
      # Core services
      guacamole = {
        enable = true;
        ip = "192.168.99.16";
        hostname = "guacamole.nixmox.lan";
        depends_on = ["postgresql", "caddy", "authentik"];
        health_check = "systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server";
        restart_policy = "unless-stopped";
        resources = {
          memory = "2GB";
          cpu = "2 cores";
          storage = "10GB";
        };
        ports = [8280, 4822];
        environment = {
          GUACD_HOSTNAME = "localhost";
          GUACD_PORT = "4822";
        };
      };
    };
    
    # Deployment phases
    deployment_phases = {
      phase1 = ["postgresql", "caddy"];           # Infrastructure
      phase2 = ["authentik"];                     # Identity
      phase3 = ["guacamole"];                     # Core services
    };
    
    # Health check timeouts
    health_check_timeout = 300;  # 5 minutes
    retry_attempts = 3;
    retry_delay = 10;            # seconds
  };
}