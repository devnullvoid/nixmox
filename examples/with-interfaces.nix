# NixMox service manifest example with service interfaces
# This shows how to implement the service interfaces for the orchestrator

{ config, lib, ... }:

let
  # Import the service interface schema
  serviceInterface = import ../lib/service-interface.nix { inherit lib config; };
  
  # Helper function to create a service interface
  mkServiceInterface = attrs: attrs;

in {
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
    
    # Core services (always required)
    core_services = {
      dns = {
        enable = true;
        ip = "192.168.99.13";
        hostname = "dns.nixmox.lan";
        interface = mkServiceInterface {
          terraform = {
            modules = [./terraform/dns];
            variables = {
              domain = "nixmox.lan";
              network_cidr = "192.168.99.0/24";
            };
            targets = ["dns_zone" "dns_records"];
          };
          
          proxy = {
            domain = "dns.nixmox.lan";
            path = "/";
            upstream = "localhost:53";
            tls = true;
            authz = false;
          };
          
          health = {
            startup = "systemctl is-active --quiet unbound";
            liveness = "systemctl is-active --quiet unbound";
            readiness = "nslookup google.com localhost > /dev/null 2>&1";
            timeout = 60;
            interval = 30;
            retries = 3;
          };
        };
      };
      
      postgresql = {
        enable = true;
        ip = "192.168.99.11";
        hostname = "postgresql.nixmox.lan";
        interface = mkServiceInterface {
          terraform = {
            modules = [./terraform/postgresql];
            variables = {
              database_name = "nixmox";
              admin_user = "postgres";
            };
            targets = ["database" "admin_role"];
          };
          
          db = {
            mode = "terraform";
            database = "nixmox";
            role = "postgres";
          };
          
          health = {
            startup = "systemctl is-active --quiet postgresql";
            liveness = "systemctl is-active --quiet postgresql";
            readiness = "sudo -u postgres psql -c 'SELECT 1;' > /dev/null 2>&1";
            timeout = 120;
            interval = 30;
            retries = 3;
          };
        };
      };
      
      caddy = {
        enable = true;
        ip = "192.168.99.10";
        hostname = "caddy.nixmox.lan";
        interface = mkServiceInterface {
          terraform = {
            modules = [./terraform/caddy];
            variables = {
              admin_port = 2019;
              http_port = 80;
              https_port = 443;
            };
            targets = ["caddy_config"];
          };
          
          proxy = {
            domain = "caddy.nixmox.lan";
            path = "/";
            upstream = "localhost:2019";
            tls = true;
            authz = false;
          };
          
          health = {
            startup = "systemctl is-active --quiet caddy";
            liveness = "curl -f -s http://localhost:2019/health";
            timeout = 60;
            interval = 30;
            retries = 3;
          };
        };
      };
      
      authentik = {
        enable = true;
        ip = "192.168.99.12";
        hostname = "authentik.nixmox.lan";
        interface = mkServiceInterface {
          terraform = {
            modules = [./terraform/authentik];
            variables = {
              admin_email = "admin@nixmox.lan";
              secret_key = "your-secret-key-here";
            };
            targets = ["authentik_core"];
          };
          
          auth = {
            type = "local";
            provider = "authentik";
          };
          
          proxy = {
            domain = "authentik.nixmox.lan";
            path = "/";
            upstream = "localhost:9000";
            tls = true;
            authz = false;
          };
          
          health = {
            startup = "systemctl is-active --quiet authentik";
            liveness = "curl -f -s http://localhost:9000/health";
            timeout = 120;
            interval = 30;
            retries = 3;
          };
        };
      };
    };
    
    # Optional services
    services = {
      guacamole = {
        enable = true;
        ip = "192.168.99.16";
        hostname = "guacamole.nixmox.lan";
        depends_on = ["postgresql" "caddy" "authentik"];
        
        interface = mkServiceInterface {
          terraform = {
            modules = [./terraform/guacamole];
            variables = {
              domain = "guac.nixmox.lan";
              callback_uris = ["https://guac.nixmox.lan/oidc/callback"];
            };
            targets = ["authentik_app" "authentik_provider" "db_schema"];
            apply_order = ["authentik_app" "authentik_provider" "db_schema"];
          };
          
          auth = {
            type = "oidc";
            provider = "authentik";
            oidc = {
              redirect_uris = ["https://guac.nixmox.lan/oidc/callback"];
              scopes = ["openid" "email" "profile"];
              username_claim = "preferred_username";
              groups_claim = "groups";
            };
          };
          
          db = {
            mode = "terraform";
            database = "guacamole";
            role = "guacamole";
            schema_files = [./schema/guacamole.sql];
          };
          
          proxy = {
            domain = "guac.nixmox.lan";
            path = "/guacamole";
            upstream = "localhost:8280";
            headers = {
              "X-Forwarded-For" = "{remote_host}";
              "X-Forwarded-Proto" = "{scheme}";
              "X-Forwarded-Host" = "{host}";
            };
            tls = true;
            authz = true;
          };
          
          health = {
            startup = "systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server";
            liveness = "curl -f -s http://localhost:8280/guacamole/";
            readiness = "curl -f -s http://localhost:8280/guacamole/api/session/tunnels/active";
            timeout = 300;
            interval = 30;
            retries = 5;
          };
        };
      };
      
      vaultwarden = {
        enable = true;
        ip = "192.168.99.14";
        hostname = "vaultwarden.nixmox.lan";
        depends_on = ["postgresql" "caddy" "authentik"];
        
        interface = mkServiceInterface {
          terraform = {
            modules = [./terraform/vaultwarden];
            variables = {
              domain = "vault.nixmox.lan";
              callback_uris = ["https://vault.nixmox.lan/oidc/callback"];
            };
            targets = ["authentik_app" "authentik_provider" "db_schema"];
            apply_order = ["authentik_app" "authentik_provider" "db_schema"];
          };
          
          auth = {
            type = "oidc";
            provider = "authentik";
            oidc = {
              redirect_uris = ["https://vault.nixmox.lan/oidc/callback"];
              scopes = ["openid" "email" "profile"];
              username_claim = "preferred_username";
              groups_claim = "groups";
            };
          };
          
          db = {
            mode = "terraform";
            database = "vaultwarden";
            role = "vaultwarden";
          };
          
          proxy = {
            domain = "vault.nixmox.lan";
            path = "/";
            upstream = "localhost:8080";
            tls = true;
            authz = true;
          };
          
          health = {
            startup = "systemctl is-active --quiet vaultwarden";
            liveness = "curl -f -s http://localhost:8080/health";
            timeout = 120;
            interval = 30;
            retries = 3;
          };
        };
      };
    };
    
    # Deployment phases
    deployment_phases = {
      phase1 = ["dns" "postgresql" "caddy"];           # Infrastructure
      phase2 = ["authentik"];                           # Identity
      phase3 = ["vaultwarden" "guacamole"];             # Core services
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