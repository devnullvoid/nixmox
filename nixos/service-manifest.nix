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
    
    # SSH authorized keys for all hosts
    ssh_keys = {
      nixmox = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkkp4yJcYNvDdzWfpHH5ZCeRrGRvL7fT18IJprgImVq jon@procyon"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDGV1JMc1cv8KrXdgXWrz5CwoKvNqZbVr7Mf4xLv7QJBcDiGeAOapgVPGHQ98Yzde+Yytrg65D66gPN8f/CVm+1nIsiLl4EEyzJ4WOQaDoiaNMfsfwpnZs5c5k15wwVMJyx/rLp6Q8ZZUl0drQ3m9BfKLHi+Y6DPNkmif9AE1GgXH0J+bYcWCjWhy67URcDQl8i6cmBYjnvbmpsbDEw+/chQ5LFutksIE9wZSyWRIHL5gmNQMJ/lP/iafRzWo/RuqJHdQio39qLzl2/r1shBU7T5zG/PBGltrpE1EVOsP42EdldGkdbgBHOu5nMKB4orc0dTEf24cA+tj2DwFOgVmHKMUO0YxSLJzoBJoc8im+ka0JhNpykPeoEjblrUtxAkWxVl8Z1Iaa1Uolx9+PeG7ZXAzRoXHa+deW6sYxZWMa52DLR/VZCA2JwVdHO0ZP4P4OLQlmVsw9Zjw2M9u68++3VIiAf0oV/IY81Fbg4527fvtRtdkQMVKcNmSBcQAANiPpBhL7RJ5gVz6e1P382+cV2c6ILe0pP8+MSs9/WLEGl6z9ftdJxyEl4I279+zFLAUsqmbcn47780c0c0xPGJU8NKY76H93jKt00wNqdFLmlWPLvAOXuURkjJIadwDRM7LrCzrxrGSoFRebiU9LNV4jsiq8PP0VaqTPyETpMQYUpd9w== jon@l33tbuntu"
      ];
      root = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkkp4yJcYNvDdzWfpHH5ZCeRrGRvL7fT18IJprgImVq jon@procyon"
      ];
    };
    
    # Authentik outpost configuration
    outposts = {
      ldap = {
        base_dn = "dc=nixmox,dc=lan";
      };
      radius = {
        shared_secret = "radius_secret_change_me";
        client_networks = ["0.0.0.0/0"];
      };
    };
  };

  # Core services (always required, deployed first)
  core_services = {
    dns = {
      enable = true;
      ip = "192.168.99.13";
      hostname = "dns.nixmox.lan";
      vmid = 904;
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 16;
      };
      onboot = true;
      start = true;
      interface = {
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
      vmid = 902;
      version = "1.0";
      resources = {
        cores = 4;
        memory = 4096;
        disk_gb = 64;
      };
      onboot = true;
      start = true;
      interface = {
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            client_id = "pgadmin-oidc";
            client_type = "confidential";
            redirect_uris = [ "https://pgadmin.nixmox.lan/oauth2/authorize" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "pgadmin.nixmox.lan";
          path = "/";
          upstream = "192.168.99.11:5050";
        };
        health = {
          startup = "systemctl is-active --quiet postgresql && systemctl is-active --quiet pgadmin";
          liveness = "systemctl is-active --quiet postgresql && systemctl is-active --quiet pgadmin";
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
      vmid = 901;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 16;
      };
      onboot = true;
      start = true;
      interface = {
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
      vmid = 903;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 16;
      };
      onboot = true;
      start = true;
      interface = {
        db = {
          host = "192.168.99.11";
          name = "authentik";
          owner = "authentik";
          port = 5432;
        };

        proxy = {
          domain = "auth.nixmox.lan";
          path = "/";
          upstream = "192.168.99.12:9000";
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
      vmid = 905;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 16;
      };
      onboot = true;
      start = true;
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8080 ];
      interface = {
        db = {
          host = "192.168.99.11";
          name = "vaultwarden";
          owner = "vaultwarden";
          port = 5432;
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            client_type = "confidential";
            redirect_uris = [ "https://vault.nixmox.lan/identity/connect/oidc-signin" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "vault.nixmox.lan";
          path = "/";
          upstream = "192.168.99.14:8080";
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
      vmid = 907;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 16;
      };
      onboot = true;
      start = true;
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8280 4822 ];
      interface = {
        db = {
          host = "192.168.99.11";
          name = "guacamole";
          owner = "guacamole";
          port = 5432;
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            client_id = "guacamole-oidc";
            client_type = "public";
            redirect_uris = [ "https://guac.nixmox.lan/guacamole/" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "guac.nixmox.lan";
          path = "/guacamole";
          upstream = "192.168.99.16:8280";
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
      vmid = 909;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 16;
      };
      onboot = true;
      start = true;
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 9090 3000 9093 ];
      interface = {
        db = {
          host = "192.168.99.11";
          name = "monitoring";
          owner = "monitoring";
          port = 5432;
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            client_id = "monitoring-oidc";
            client_type = "confidential";
            redirect_uris = [ "https://grafana.nixmox.lan/login/generic_oauth" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        # Multi-proxy configuration for monitoring services
        proxy = {
          prometheus = {
            domain = "prometheus.nixmox.lan";
            path = "/";
            upstream = "192.168.99.18:9090";
          };
          grafana = {
            domain = "grafana.nixmox.lan";
            path = "/";
            upstream = "192.168.99.18:3000";
          };
          alertmanager = {
            domain = "alertmanager.nixmox.lan";
            path = "/";
            upstream = "192.168.99.18:9093";
          };
          loki = {
            domain = "loki.nixmox.lan";
            path = "/";
            upstream = "192.168.99.18:3100";
          };
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
      vmid = 906;
      version = "1.0";
      resources = {
        cores = 4;
        memory = 4096;
        disk_gb = 32;
      };
      onboot = true;
      start = true;
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8080 ];
      interface = {
        db = {
          host = "192.168.99.11";
          name = "nextcloud";
          owner = "nextcloud";
          port = 5432;
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            client_type = "confidential";
            redirect_uris = [ "https://cloud.nixmox.lan/apps/user_oidc/code" ];
            scopes = [ "email" "profile" "nextcloud" "openid" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "cloud.nixmox.lan";
          path = "/";
          upstream = "192.168.99.15:80";
        };
        health = {
          startup = "systemctl is-active --quiet nextcloud";
          liveness = "curl -f -s http://localhost:80/status.php";
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
      vmid = 908;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 32;
      };
      onboot = true;
      start = true;
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 8096 8989 7878 9696 9091 ];
      interface = {
        # Multiple database configuration for media services
        dbs = {
          sonarr = {
            host = "192.168.99.11";
            name = "sonarr";
            owner = "sonarr";
            port = 5432;
            additionaldbs = [ "sonarr-log" ];
          };
          radarr = {
            host = "192.168.99.11";
            name = "radarr";
            owner = "radarr";
            port = 5432;
            additionaldbs = [ "radarr-log" ];
          };
          prowlarr = {
            host = "192.168.99.11";
            name = "prowlarr";
            owner = "prowlarr";
            port = 5432;
            additionaldbs = [ "prowlarr-log" ];
          };
          # transmission doesn't need a database
        };
        
        # Multi-proxy configuration for media services with per-service auth
        proxy = {
          jellyfin = {
            domain = "jellyfin.nixmox.lan";
            path = "/";
            upstream = "192.168.99.17:8096";
            auth = {
              type = "oidc";
              provider = "authentik";
              oidc = {
                client_type = "confidential";
                redirect_uris = [ "https://jellyfin.nixmox.lan/oidc/callback" ];
                scopes = [ "openid" "email" "profile" ];
                username_claim = "preferred_username";
                groups_claim = "groups";
              };
            };
            extra_config = ''
              # Jellyfin-specific headers
              header {
                # Enable CORS
                Access-Control-Allow-Origin "*"
                Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
                Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization"
                
                # Security headers
                X-Content-Type-Options nosniff
                X-Frame-Options DENY
                X-XSS-Protection "1; mode=block"
              }
              
              # Handle preflight requests
              @options {
                method OPTIONS
              }
              respond @options 200
            '';
          };
          sonarr = {
            domain = "sonarr.nixmox.lan";
            path = "/";
            upstream = "192.168.99.17:8989";
            auth = {
              type = "forward_auth";
              provider = "authentik";
              forward_auth_upstream = "192.168.99.12:9000";
            };
          };
          radarr = {
            domain = "radarr.nixmox.lan";
            path = "/";
            upstream = "192.168.99.17:7878";
            auth = {
              type = "forward_auth";
              provider = "authentik";
              forward_auth_upstream = "192.168.99.12:9000";
            };
          };
          prowlarr = {
            domain = "prowlarr.nixmox.lan";
            path = "/";
            upstream = "192.168.99.17:9696";
            auth = {
              type = "forward_auth";
              provider = "authentik";
              forward_auth_upstream = "192.168.99.12:9000";
            };
          };
          transmission = {
            domain = "transmission.nixmox.lan";
            path = "/";
            upstream = "192.168.99.17:9091";
            auth = {
              type = "forward_auth";
              provider = "authentik";
              forward_auth_upstream = "192.168.99.12:9000";
            };
          };
        };
        
        health = {
          startup = "systemctl is-active --quiet jellyfin && systemctl is-active --quiet sonarr && systemctl is-active --quiet radarr && systemctl is-active --quiet prowlarr && systemctl is-active --quiet transmission";
          liveness = "systemctl is-active --quiet jellyfin && systemctl is-active --quiet sonarr && systemctl is-active --quiet radarr && systemctl is-active --quiet prowlarr && systemctl is-active --quiet transmission";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    mail = {
      enable = false;
      ip = "192.168.99.19";
      hostname = "mail.nixmox.lan";
      vmid = 910;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 16;
      };
      onboot = true;
      start = true;
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 25 587 ];  # Basic SMTP ports only
      interface = {
        health = {
          startup = "systemctl is-active --quiet postfix";
          liveness = "systemctl is-active --quiet postfix";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    openbao = {
      enable = true;
      ip = "192.168.99.20";
      hostname = "openbao.nixmox.lan";
      vmid = 911;
      version = "1.0";
      resources = {
        cores = 2;
        memory = 2048;
        disk_gb = 32;
      };
      onboot = true;
      start = true;
      depends_on = [ "caddy" "authentik" ];
      ports = [ 8200 ];
      interface = {
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            client_id = "openbao-oidc";
            client_type = "confidential";
            redirect_uris = [ "https://bao.nixmox.lan/oidc/callback" "https://bao.nixmox.lan/ui/vault/auth/oidc/oidc/callback" "http://localhost:8200/oidc/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "bao.nixmox.lan";
          path = "/";
          upstream = "192.168.99.20:8200";
        };
        health = {
          startup = "systemctl is-active --quiet openbao";
          liveness = "curl -f -s http://localhost:8200/v1/sys/health";
          interval = 30;
          timeout = 60;
          retries = 3;
        };
      };
    };

    forgejo = {
      enable = true;
      ip = "192.168.99.21";
      hostname = "forgejo.nixmox.lan";
      vmid = 912;
      version = "1.0";
      resources = {
        cores = 4;
        memory = 4096;
        disk_gb = 64;
      };
      onboot = true;
      start = true;
      depends_on = [ "postgresql" "caddy" "authentik" ];
      ports = [ 3000 ];
      interface = {
        db = {
          host = "192.168.99.11";
          name = "forgejo";
          owner = "forgejo";
          port = 5432;
        };
        auth = {
          type = "oidc";
          provider = "authentik";
          oidc = {
            client_type = "confidential";
            redirect_uris = [ "https://git.nixmox.lan/user/oauth2/authentik/callback" ];
            scopes = [ "openid" "email" "profile" ];
            username_claim = "preferred_username";
            groups_claim = "groups";
          };
        };
        proxy = {
          domain = "git.nixmox.lan";
          path = "/";
          upstream = "192.168.99.21:3000";
        };
        health = {
          startup = "systemctl is-active --quiet forgejo";
          liveness = "curl -f -s http://localhost:3000/api/v1/version";
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
    services = [ "vaultwarden" "guacamole" "monitoring" "nextcloud" "media" "mail" "openbao" "forgejo" ];
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
