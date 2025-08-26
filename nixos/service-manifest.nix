# NixMox Service Manifest
# This manifest defines our existing infrastructure and can be used by the orchestrator
# to deploy and manage all services in the correct order.
#
# DNS Architecture:
# - Each host has its own A record: hostname.nixmox.lan -> IP (e.g., guacamole.nixmox.lan -> 192.168.99.16)
# - Service domains use CNAME records pointing to caddy.nixmox.lan (e.g., guac.nixmox.lan -> caddy.nixmox.lan)
# - Base domain: nixmox.lan (global domain for all services)

{
  # Network infrastructure configuration
  network = {
    domain = "nixmox.lan";  # Global base domain for all services
    dns_server = "192.168.99.13";
    gateway = "192.168.99.1";
    network_cidr = "192.168.99.0/24";
    vlan_tag = 99;
  };

  # Core services (always required, deployed first)
  core_services = {
    dns = {
      enable = true;
      ip = "192.168.99.13";
      hostname = "dns.nixmox.lan";
      interface = {
        terraform = {
          modules = [ "./terraform/dns" ];
          variables = {
            domain = "nixmox.lan";
            network_cidr = "192.168.99.0/24";
          };
        };
        proxy = {
          domain = "dns.nixmox.lan";
          path = "/";
          upstream = "192.168.99.13:53";
          tls = true;
          authz = false;
        };
        health = {
          startup = "systemctl is-active --quiet unbound";
          liveness = "systemctl is-active --quiet unbound";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    postgresql = {
      enable = true;
      ip = "192.168.99.11";
      hostname = "postgresql.nixmox.lan";
      interface = {
        terraform = {
          modules = [ "./terraform/postgresql" ];
          variables = {
            domain = "nixmox.lan";
            network_cidr = "192.168.99.0/24";
          };
        };
        db = {
          name = "postgresql";
          port = 5432;
          mode = "standalone";
        };
        proxy = {
          domain = "postgresql.nixmox.lan";
          path = "/";
          upstream = "192.168.99.11:5432";
          tls = true;
          authz = false;
        };
        health = {
          startup = "systemctl is-active --quiet postgresql";
          liveness = "systemctl is-active --quiet postgresql";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    caddy = {
      enable = true;
      ip = "192.168.99.10";
      hostname = "caddy.nixmox.lan";
      interface = {
        terraform = {
          modules = [ "./terraform/caddy" ];
          variables = {
            domain = "nixmox.lan";
            network_cidr = "192.168.99.0/24";
          };
        };
        proxy = {
          domain = "caddy.nixmox.lan";
          path = "/";
          upstream = "192.168.99.10:80";
          tls = true;
          authz = false;
        };
        health = {
          startup = "systemctl is-active --quiet caddy";
          liveness = "systemctl is-active --quiet caddy";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    authentik = {
      enable = true;
      ip = "192.168.99.12";
      hostname = "authentik.nixmox.lan";
      interface = {
        terraform = {
          modules = [ "./terraform/authentik" ];
          variables = {
            domain = "nixmox.lan";
            network_cidr = "192.168.99.0/24";
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://auth.nixmox.lan/*" ];
            scopes = [ "openid" "email" "profile" "offline_access" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "auth.nixmox.lan";
          path = "/";
          upstream = "192.168.99.12:9000";
          tls = true;
          authz = false;
        };
        health = {
          startup = "systemctl is-active --quiet authentik";
          liveness = "systemctl is-active --quiet authentik";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };
  };

  # Application services (deployed after core services)
  services = {
    vaultwarden = {
      enable = true;
      ip = "192.168.99.14";
      hostname = "vaultwarden.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8080 ];
      interface = {
        terraform = {
          modules = [ "./terraform/vaultwarden" ];
          targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
          variables = {
            domain = "nixmox.lan";
            oidc_client_id = "vaultwarden-oidc";
            oidc_scopes = [ "openid" "email" "profile" ];
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://vaultwarden.nixmox.lan/oidc/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "vault.nixmox.lan";
          path = "/";
          upstream = "192.168.99.14:8080";
          tls = true;
          authz = true;
        };
        health = {
          startup = "systemctl is-active --quiet vaultwarden";
          liveness = "curl -f -s http://localhost:8080/alive";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    guacamole = {
      enable = true;
      ip = "192.168.99.16";
      hostname = "guacamole.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8280 4822 ];
      interface = {
        terraform = {
          modules = [ "./terraform/guacamole" ];
          targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
          variables = {
            domain = "nixmox.lan";
            oidc_client_id = "guacamole-client";
            oidc_scopes = [ "openid" "email" "profile" ];
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://guac.nixmox.lan/guacamole/*" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "guac.nixmox.lan";
          path = "/guacamole/";
          upstream = "192.168.99.16:8280";
          tls = true;
          authz = true;
        };
        health = {
          startup = "systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server";
          liveness = "systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    monitoring = {
      enable = true;
      ip = "192.168.99.18";
      hostname = "monitoring.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 9090 3000 9093 ];
      interface = {
        terraform = {
          modules = [ "./terraform/monitoring" ];
          targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
          variables = {
            domain = "nixmox.lan";
            oidc_client_id = "monitoring-oidc";
            oidc_scopes = [ "openid" "email" "profile" ];
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://monitoring.nixmox.lan/oidc/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "monitoring.nixmox.lan";
          path = "/";
          upstream = "192.168.99.18:9090";
          tls = true;
          authz = true;
        };
        health = {
          startup = "systemctl is-active --quiet prometheus && systemctl is-active --quiet grafana";
          liveness = "systemctl is-active --quiet prometheus && systemctl is-active --quiet grafana";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    nextcloud = {
      enable = true;
      ip = "192.168.99.15";
      hostname = "nextcloud.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8080 ];
      interface = {
        terraform = {
          modules = [ "./terraform/nextcloud" ];
          targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
          variables = {
            domain = "nixmox.lan";
            oidc_client_id = "nextcloud-oidc";
            oidc_scopes = [ "openid" "email" "profile" ];
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://nextcloud.nixmox.lan/oidc/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "nextcloud.nixmox.lan";
          path = "/";
          upstream = "192.168.99.15:8080";
          tls = true;
          authz = true;
        };
        health = {
          startup = "systemctl is-active --quiet nextcloud";
          liveness = "curl -f -s http://localhost:8080/status.php";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    media = {
      enable = true;
      ip = "192.168.99.17";
      hostname = "media.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8096 8097 8098 ];
      interface = {
        terraform = {
          modules = [ "./terraform/media" ];
          targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
          variables = {
            domain = "nixmox.lan";
            oidc_client_id = "media-oidc";
            oidc_scopes = [ "openid" "email" "profile" ];
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://media.nixmox.lan/oidc/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "media.nixmox.lan";
          path = "/";
          upstream = "192.168.99.17:8096";
          tls = true;
          authz = true;
        };
        health = {
          startup = "systemctl is-active --quiet jellyfin && systemctl is-active --quiet sonarr && systemctl is-active --quiet radarr";
          liveness = "systemctl is-active --quiet jellyfin && systemctl is-active --quiet sonarr && systemctl is-active --quiet radarr";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    mail = {
      enable = true;
      ip = "192.168.99.19";
      hostname = "mail.nixmox.lan";
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 25 587 465 993 995 ];
      interface = {
        terraform = {
          modules = [ "./terraform/mail" ];
          targets = [ "authentik_app" "authentik_provider" "authentik_outpost" ];
          variables = {
            domain = "nixmox.lan";
            oidc_client_id = "mail-oidc";
            oidc_scopes = [ "openid" "email" "profile" ];
          };
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            redirect_uris = [ "https://mail.nixmox.lan/oidc/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "mail.nixmox.lan";
          path = "/";
          upstream = "192.168.99.19:8080";
          tls = true;
          authz = true;
        };
        health = {
          startup = "systemctl is-active --quiet postfix && systemctl is-active --quiet dovecot";
          liveness = "systemctl is-active --quiet postfix && systemctl is-active --quiet dovecot";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };
  };

  # Deployment configuration
  deployment_phases = {
    tf_infra = [ "postgresql" "dns" "caddy" "authentik" ];
    nix_core = [ "postgresql" "dns" "caddy" "authentik" ];
    tf_auth_core = [ "authentik" ];
    services = [ "vaultwarden" "guacamole" "monitoring" "nextcloud" "media" "mail" ];
  };

  # Health check configuration
  health_check_timeout = 600;
  retry_attempts = 5;
  retry_delay = 15;

  # Advanced options
  enable_rollback = true;
  enable_health_monitoring = true;
  enable_dependency_graphing = true;
  enable_deployment_logging = true;
}
