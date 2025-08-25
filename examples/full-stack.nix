# Full-stack NixMox service manifest example
# This shows how to define a complete service infrastructure

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
      dns = {
        enable = true;
        ip = "192.168.99.13";
        hostname = "dns.nixmox.lan";
        depends_on = [];
        health_check = "systemctl is-active --quiet unbound";
        restart_policy = "unless-stopped";
        resources = {
          memory = "512MB";
          cpu = "1 core";
          storage = "2GB";
        };
        ports = [53];
        volumes = ["/etc/unbound:/etc/unbound"];
      };
      
      postgresql = {
        enable = true;
        ip = "192.168.99.11";
        hostname = "postgresql.nixmox.lan";
        depends_on = ["dns"];
        health_check = "systemctl is-active --quiet postgresql";
        restart_policy = "unless-stopped";
        resources = {
          memory = "4GB";
          cpu = "2 cores";
          storage = "50GB";
        };
        ports = [5432];
        volumes = ["/var/lib/postgresql:/var/lib/postgresql"];
        environment = {
          POSTGRES_PASSWORD = "your-secure-password";
          POSTGRES_DB = "nixmox";
        };
      };
      
      caddy = {
        enable = true;
        ip = "192.168.99.10";
        hostname = "caddy.nixmox.lan";
        depends_on = ["dns"];
        health_check = "curl -f -s http://localhost:2019/health";
        restart_policy = "unless-stopped";
        resources = {
          memory = "1GB";
          cpu = "1 core";
          storage = "5GB";
        };
        ports = [80, 443, 2019];
        volumes = ["/etc/caddy:/etc/caddy"];
      };
      
      # Identity and security
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
          storage = "15GB";
        };
        ports = [9000];
        environment = {
          AUTHENTIK_SECRET_KEY = "your-secret-key-here";
          AUTHENTIK_POSTGRESQL__HOST = "postgresql.nixmox.lan";
          AUTHENTIK_REDIS__HOST = "redis.nixmox.lan";
        };
      };
      
      # Core services
      vaultwarden = {
        enable = true;
        ip = "192.168.99.14";
        hostname = "vaultwarden.nixmox.lan";
        depends_on = ["postgresql", "caddy", "authentik"];
        health_check = "curl -f -s http://localhost:8080/health";
        restart_policy = "unless-stopped";
        resources = {
          memory = "1GB";
          cpu = "1 core";
          storage = "10GB";
        };
        ports = [8080];
        environment = {
          DATABASE_URL = "postgresql://vaultwarden:password@postgresql.nixmox.lan:5432/vaultwarden";
          DOMAIN = "https://vault.nixmox.lan";
        };
      };
      
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
          POSTGRESQL_HOST = "postgresql.nixmox.lan";
        };
      };
      
      # Storage and media
      nextcloud = {
        enable = true;
        ip = "192.168.99.15";
        hostname = "nextcloud.nixmox.lan";
        depends_on = ["postgresql", "caddy", "authentik"];
        health_check = "curl -f -s http://localhost:8080/status.php";
        restart_policy = "unless-stopped";
        resources = {
          memory = "4GB";
          cpu = "2 cores";
          storage = "100GB";
        };
        ports = [8080];
        volumes = ["/var/www/nextcloud:/var/www/nextcloud"];
        environment = {
          MYSQL_HOST = "postgresql.nixmox.lan";
          NEXTCLOUD_DOMAIN = "cloud.nixmox.lan";
        };
      };
      
      media = {
        enable = true;
        ip = "192.168.99.17";
        hostname = "media.nixmox.lan";
        depends_on = ["postgresql", "caddy"];
        health_check = "systemctl is-active --quiet jellyfin";
        restart_policy = "unless-stopped";
        resources = {
          memory = "8GB";
          cpu = "4 cores";
          storage = "2TB";
        };
        ports = [8096, 8920];
        volumes = ["/media:/media", "/config:/config"];
        environment = {
          JELLYFIN_PUBLISHED_SERVER_URL = "https://media.nixmox.lan";
        };
      };
      
      # Monitoring and observability
      monitoring = {
        enable = true;
        ip = "192.168.99.18";
        hostname = "monitoring.nixmox.lan";
        depends_on = ["postgresql", "caddy"];
        health_check = "curl -f -s http://localhost:9090/-/healthy";
        restart_policy = "unless-stopped";
        resources = {
          memory = "2GB";
          cpu = "2 cores";
          storage = "20GB";
        };
        ports = [9090, 3000, 9091];
        volumes = ["/var/lib/prometheus:/var/lib/prometheus"];
        environment = {
          PROMETHEUS_STORAGE_PATH = "/var/lib/prometheus";
          GRAFANA_SERVER_ROOT_URL = "https://monitoring.nixmox.lan";
        };
      };
      
      # Mail services
      mail = {
        enable = true;
        ip = "192.168.99.19";
        hostname = "mail.nixmox.lan";
        depends_on = ["postgresql", "caddy", "dns"];
        health_check = "systemctl is-active --quiet postfix && systemctl is-active --quiet dovecot";
        restart_policy = "unless-stopped";
        resources = {
          memory = "2GB";
          cpu = "2 cores";
          storage = "25GB";
        };
        ports = [25, 587, 993, 995];
        volumes = ["/var/mail:/var/mail", "/var/vmail:/var/vmail"];
        environment = {
          POSTFIX_HOSTNAME = "mail.nixmox.lan";
          DOVECOT_HOSTNAME = "mail.nixmox.lan";
        };
      };
    };
    
    # Deployment phases
    deployment_phases = {
      phase1 = ["dns", "postgresql", "caddy"];                    # Infrastructure
      phase2 = ["authentik"];                                      # Identity
      phase3 = ["vaultwarden", "guacamole"];                       # Core services
      phase4 = ["nextcloud", "media"];                             # Storage and media
      phase5 = ["monitoring"];                                     # Monitoring
      phase6 = ["mail"];                                           # Mail services
    };
    
    # Health check configuration
    health_check_timeout = 600;  # 10 minutes for complex services
    retry_attempts = 5;
    retry_delay = 15;            # seconds
    
    # Advanced options
    enable_rollback = true;
    enable_health_monitoring = true;
    enable_dependency_graphing = true;
    enable_deployment_logging = true;
  };
}