# Caddy service definitions for the dedicated reverse proxy container
# This file defines all the services that Caddy will proxy to other containers

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
  baseDomain = cfg.domain;
in {
  config = mkIf cfg.enable {
    # Configure all services to be proxied through Caddy
    services.nixmox.caddy.services = {
      # Authentik service
      authentik = {
        domain = "auth.${baseDomain}";
        backend = "192.168.99.12";
        port = 9000;
        enableAuth = false; # No auth for Authentik itself
        extraConfig = ''
          # Authentik-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Nextcloud service
      nextcloud = {
        domain = "nextcloud.${baseDomain}";
        backend = "nextcloud.nixmox.lan";
        port = 8080;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Nextcloud-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options DENY
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }

          # Handle Nextcloud-specific paths
          @nc {
            path /remote.php /dav /status.php /updater /ocs /index.php /robots.txt /.well-known
          }

          # Proxy to Nextcloud for specific paths
          reverse_proxy @nc nextcloud.nixmox.lan:8080
        '';
      };

      # Jellyfin service
      jellyfin = {
        domain = "media.${baseDomain}";
        backend = "media.nixmox.lan";
        port = 8096;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Jellyfin-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Sonarr service
      sonarr = {
        domain = "sonarr.${baseDomain}";
        backend = "media.nixmox.lan";
        port = 8989;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Sonarr-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Radarr service
      radarr = {
        domain = "radarr.${baseDomain}";
        backend = "media.nixmox.lan";
        port = 7878;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Radarr-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Prowlarr service
      prowlarr = {
        domain = "prowlarr.${baseDomain}";
        backend = "media.nixmox.lan";
        port = 9696;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Prowlarr-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Transmission service
      transmission = {
        domain = "transmission.${baseDomain}";
        backend = "media.nixmox.lan";
        port = 9091;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Transmission-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Grafana service
      grafana = {
        domain = "monitoring.${baseDomain}";
        backend = "monitoring.nixmox.lan";
        port = 3000;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Grafana-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Prometheus service
      prometheus = {
        domain = "prometheus.${baseDomain}";
        backend = "monitoring.nixmox.lan";
        port = 9090;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Prometheus-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Alertmanager service
      alertmanager = {
        domain = "alertmanager.${baseDomain}";
        backend = "monitoring.nixmox.lan";
        port = 9093;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Alertmanager-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options SAMEORIGIN
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

      # Guacamole service
      guacamole = {
        domain = "guac.${baseDomain}";
        backend = "guacamole.nixmox.lan";
        port = 8280;
        enableAuth = true; # Enable Authentik forward auth
        skipDefaultProxy = true; # Handle proxying manually in extraConfig
        extraConfig = ''
          # Guacamole reverse proxy configuration
          # Based on https://guacamole.apache.org/doc/gug/reverse-proxy.html
          
          # Add proper headers for reverse proxy to prevent redirect loops
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
          
          # Simple reverse proxy - let Guacamole handle all paths including OIDC redirects
          reverse_proxy guacamole.nixmox.lan:8280
        '';
      };

      # Vaultwarden service (internal container access)
      vaultwarden = {
        domain = "vault.${baseDomain}";
        backend = "vaultwarden.nixmox.lan";
        port = 8080;
        enableAuth = true; # Enable Authentik forward auth
        extraConfig = ''
          # Vaultwarden-specific Caddy configuration
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options DENY
            X-XSS-Protection "1; mode=block"
            Referrer-Policy strict-origin-when-cross-origin
            # Remove server header
            -Server
          }
        '';
      };

    };
  };
}
