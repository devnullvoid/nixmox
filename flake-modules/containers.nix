{ lib, inputs, ... }:

let
  # Common configuration for all containers
  commonConfig = { config, pkgs, lib, ... }: {
    imports = [
      # SOPS for secrets management
      inputs.sops-nix.nixosModules.sops

      # Common modules
      ../modules/common
    ];

    # Enable common services
    services.nixmox.enable = true;

    # Container-specific settings
    boot.isContainer = true;

    # Disable Nix sandboxing in containers (as recommended)
    nix.settings.sandbox = false;

    # Basic networking (Proxmox handles the actual network config)
    networking = {
      firewall.enable = true;
      # Keep networking services enabled but let Proxmox manage the config
      useDHCP = lib.mkForce true;
      useNetworkd = lib.mkForce true;
    };

    # Enable SSH for management
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkForce "yes"; # Temporary for bootstrapping
        PasswordAuthentication = lib.mkForce true; # Temporary for bootstrapping
      };
    };

    # Configure root user with SSH keys
    users.users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkkp4yJcYNvDdzWfpHH5ZCeRrGRvL7fT18IJprgImVq jon@procyon"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDGV1JMc1cv8KrXdgXWrz5CwoKvNqZbVr7Mf4xLv7QJBcDiGeAOapgVPGHQ98Yzde+Yytrg65D66gPN8f/CVm+1nIsiLl4EEyzJ4WOQaDoiaNMfsfwpnZs5c5k15wwVMJyx/rLp6Q8ZZUl0drQ3m9BfKLHi+Y6DPNkmif9AE1GgXH0J+bYcWCjWhy67URcDQl8i6cmBYjnvbmpsbDEw+/chQ5LFutksIE9wZSyWRIHL5gmNQMJ/lP/iafRzWo/RuqJHdQio39qLzl2/r1shBU7T5zG/PBGltrpE1EVOsP42EdldGkdbgBHOu5nMKB4orc0dTEf24cA+tj2DwFOgVmHKMUO0YxSLJzoBJoc8im+ka0JhNpykPeoEjblrUtxAkWxVl8Z1Iaa1Uolx9/PeG7ZXAzRoXHa+deW6sYxZWMa52DLR/VZCA2JwVdHO0ZP4P4OLQlmVsw9Zjw2M9u68++3VIiAf0oV/IY81Fbg4527fvtRtdkQMVKcNmSBcQAANiPpBhL7RJ5gVz6e1P382+cV2c6ILe0pP8+MSs9/WLEGl6z9ft0JxyEl4I279+zFLAUsqmbcn47780c0xPGJU8NKY76H93jKt00wNqdFLmlWPLvAOXuURkjJIadwDRM7LrCzrxrGSoFRebiU9LNV4jsiq8PP0VaqTPyETpMQYUpd9w== jon@l33tbuntu"
      ];
    };

    # Create a basic user for management
    users.users.nixmox = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      initialPassword = "nixmox"; # Will be changed via secrets
    };

    # Enable basic services
    services = {
      # NTP for time sync
      timesyncd.enable = true;

      # Node exporter for monitoring
      prometheus.exporters.node.enable = true;
    };

    # SOPS configuration
    sops = {
      defaultSopsFile = ../secrets/default.yaml;
      age.keyFile = "/etc/sops/age/keys.txt";

      # SOPS secrets - temporarily disabled for testing
      # secrets.nixmox_password = {
      #   sopsFile = ../secrets/default.yaml;
      #   key = "nixmox.password";
      #   mode = "0400";
      # };
    };
  };

  # Container configurations
  containers = {
    # Authentik container (POC stack: also runs Caddy and Vaultwarden)
    authentik = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/authentik
        ../modules/vaultwarden
        ../modules/vaultwarden/oci.nix
        ../modules/caddy
        ../modules/guacamole
        ../modules/localtls
        inputs.authentik-nix.nixosModules.default
      ];

      networking.hostName = "authentik";

      # Core services
      services.nixmox.authentik.enable = true;

      # Resolve local hostnames (until DNS exists); rely on modules for their own host entries
      networking.hosts."127.0.0.1" = [ ];

      # Caddy via module only
      services.nixmox.caddy.enable = true;

      # Local TLS certs used by Caddy
      services.nixmox.localtls.enable = true;

      # Firewall is managed by the Caddy module

      # Switch Vaultwarden to OCI container (module)
      services.nixmox.vaultwarden.oci.enable = true;

      # Enable Guacamole stack (Tomcat + guacd + Postgres) behind Caddy
      services.nixmox.guacamole.enable = true;
    };

    # Caddy reverse proxy container
    caddy = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/caddy
      ];

      networking.hostName = "caddy";

      # Caddy-specific settings
      services.caddy = {
        enable = true;
        # Configuration will be added in the caddy module
      };
    };

    # Monitoring container (Prometheus + Grafana)
    monitoring = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/monitoring
      ];

      networking.hostName = "monitoring";

      # Monitoring stack
      services.nixmox.monitoring.enable = true;
    };

    # Mail server container
    mail = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/mail
      ];

      networking.hostName = "mail";

      # Mail server configuration
      services.nixmox.mail.enable = true;
    };

    # Media server container (Jellyfin + Arr stack)
    media = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/media
      ];

      networking.hostName = "media";

      # Media services
      services.nixmox.media.enable = true;

      # Use external PostgreSQL
      services.nixmox.media.database = {
        type = "postgresql";
        host = "postgresql.nixmox.lan";
        port = 5432;
        name = "media";
        user = "media";
        password = "changeme"; # Should be overridden via SOPS
      };
    };

    # Nextcloud container
    nextcloud = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/nextcloud
      ];

      networking.hostName = "nextcloud";

      # Nextcloud configuration
      services.nixmox.nextcloud.enable = true;

      # Use external PostgreSQL
      services.nixmox.nextcloud.database = {
        type = "postgresql";
        host = "postgresql.nixmox.lan";
        port = 5432;
        name = "nextcloud";
        user = "nextcloud";
      };
    };

    # Vaultwarden container
    vaultwarden = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/vaultwarden
      ];

      networking.hostName = "vaultwarden";

      # Vaultwarden configuration
      services.nixmox.vaultwarden.enable = true;
    };

    # DNS container (Unbound)
    dns = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/dns
      ];

      networking.hostName = "dns";

      # DNS configuration
      services.nixmox.dns.enable = true;
    };

    # PostgreSQL database container
    postgresql = { config, pkgs, lib, ... }: {
      imports = [
        commonConfig
        ../modules/postgresql
      ];

      networking.hostName = "postgresql";

      # PostgreSQL configuration
      services.nixmox.postgresql.enable = true;

      # Default databases and users
      services.nixmox.postgresql.databases = {
        nextcloud = {
          name = "nextcloud";
          owner = "nextcloud";
          extensions = [ "pg_trgm" "btree_gin" ];
        };
        authentik = {
          name = "authentik";
          owner = "authentik";
          extensions = [ "pg_trgm" "uuid-ossp" ];
        };
        jellyfin = {
          name = "jellyfin";
          owner = "jellyfin";
          extensions = [];
        };
        media = {
          name = "media";
          owner = "media";
          extensions = [];
        };
        media_sonarr = {
          name = "media_sonarr";
          owner = "media";
          extensions = [];
        };
        media_radarr = {
          name = "media_radarr";
          owner = "media";
          extensions = [];
        };
        media_prowlarr = {
          name = "media_prowlarr";
          owner = "media";
          extensions = [];
        };
      };

      services.nixmox.postgresql.users = {
        nextcloud = {
          name = "nextcloud";
          password = "changeme"; # Should be overridden via SOPS
          databases = [ "nextcloud" ];
          superuser = false;
        };
        authentik = {
          name = "authentik";
          password = "changeme"; # Should be overridden via SOPS
          databases = [ "authentik" ];
          superuser = false;
        };
        jellyfin = {
          name = "jellyfin";
          password = "changeme"; # Should be overridden via SOPS
          databases = [ "jellyfin" ];
          superuser = false;
        };
        media = {
          name = "media";
          password = "changeme"; # Should be overridden via SOPS
          databases = [ "media" "media_sonarr" "media_radarr" "media_prowlarr" ];
          superuser = false;
        };
      };
    };
  };
in {
  # Export the containers and commonConfig for use in other modules
  _module.args = {
    inherit containers commonConfig;
  };
}
