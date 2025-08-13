{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
in {
  options.services.nixmox.caddy = {
    enable = mkEnableOption "Caddy reverse proxy";
    
    domain = mkOption {
      type = types.str;
      default = "proxy.nixmox.lan";
      description = "Domain for Caddy proxy";
    };
    
    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for services";
    };
    
    authentikDomain = mkOption {
      type = types.str;
      default = "auth.nixmox.lan";
      description = "Authentik domain for forward auth";
    };
    authentikUpstream = mkOption {
      type = types.str;
      default = "localhost:9000";
      description = "Upstream host:port for Authentik core (for reverse_proxy and forward_auth). Use IP:port when Authentik runs on another container.";
    };
    
    # Service configurations
    services = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          domain = mkOption {
            type = types.str;
            description = "Domain for this service";
          };
          backend = mkOption {
            type = types.str;
            description = "Backend service address (IP:port)";
          };
          port = mkOption {
            type = types.int;
            default = 80;
            description = "Backend service port";
          };
          enableAuth = mkOption {
            type = types.bool;
            default = true;
            description = "Enable Authentik forward auth";
          };
          extraConfig = mkOption {
            type = types.str;
            default = "";
            description = "Extra Caddy configuration";
          };
        };
      });
      default = {};
      description = "Services to proxy";
    };
  };

  config = mkIf cfg.enable {
    # Caddy service configuration
    services.caddy = {
      enable = true;
      
      # Global settings
      globalConfig = ''
        # Global Caddy settings
        {
          # Admin API (for dynamic config)
          admin off
          
          # Logging
          log {
            output file /var/log/caddy/access.log
            format json
          }
          
          # Automatic HTTPS
          auto_https disable_redirects
        }
      '';
      
      # Virtual hosts configuration
      virtualHosts = mkMerge (
        [
          # Authentik service
          {
            "${cfg.authentikDomain}" = {
              extraConfig = ''
                # Authentik service
                reverse_proxy ${cfg.authentikUpstream} {
                  header_up X-Forwarded-Proto {scheme}
                  header_up X-Forwarded-For {remote_host}
                  header_up X-Real-IP {remote_host}
                }
              '';
            };
          }
        ]
        # Service proxies with forward auth (flattened)
        ++ (mapAttrsToList (name: service: {
          "${service.domain}" = {
            extraConfig = ''
              # Forward authentication
              ${optionalString service.enableAuth ''
              route {
                forward_auth http://${cfg.authentikUpstream} {
                  uri /outpost.goauthentik.io/auth/caddy
                  copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Jwt
                  trusted_proxies private_ranges
                }
              }
              ''}
              
              # Backend service
              reverse_proxy ${service.backend}:${toString service.port} {
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-For {remote_host}
                header_up X-Real-IP {remote_host}
                header_up Host {host}
                
                # Copy Authentik headers to backend
                ${optionalString service.enableAuth ''
                header_up X-Authentik-Username {http.reverse_proxy.header.X-Authentik-Username}
                header_up X-Authentik-Groups {http.reverse_proxy.header.X-Authentik-Groups}
                header_up X-Authentik-Email {http.reverse_proxy.header.X-Authentik-Email}
                header_up X-Authentik-Jwt {http.reverse_proxy.header.X-Authentik-Jwt}
                ''}
              }
              
              # Additional configuration
              ${service.extraConfig}
            '';
          };
        }) cfg.services)
        
        # Default catch-all for unknown domains
        ++ [
          {
            "${cfg.primaryDomain}" = {
              extraConfig = ''
                # Default page
                respond "NixMox Proxy - Service not found" 404
              '';
            };
          }
        ]
      );
    };
    
    # Create log directory
    systemd.tmpfiles.rules = [
      "d /var/log/caddy 0755 caddy caddy"
    ];
    
    # Firewall rules for Caddy
    networking.firewall = {
      allowedTCPPorts = [
        80   # HTTP
        443  # HTTPS
      ];
    };
    
    # Systemd service configuration
    systemd.services.caddy = {
      # Ensure Caddy starts after network
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      # Service configuration
      serviceConfig = {
        # User and group
        User = "caddy";
        Group = "caddy";
        
        # Capabilities
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
        
        # Security settings
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        
        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
    
    # Health check for Caddy
    systemd.services.caddy-health = {
      description = "Caddy health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "caddy.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:2019/health/";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
    # Create Caddy user
    users.users.caddy = {
      isSystemUser = true;
      group = "caddy";
      home = "/var/lib/caddy";
      createHome = true;
    };
    
    users.groups.caddy = {};
    
    # Default service configurations
    services.nixmox.caddy.services = {
      # Example service configurations
      jellyfin = {
        domain = "jellyfin.${cfg.primaryDomain}";
        backend = "192.168.50.10";
        port = 8096;
        enableAuth = true;
      };
      
      nextcloud = {
        domain = "nextcloud.${cfg.primaryDomain}";
        backend = "192.168.50.11";
        port = 80;
        enableAuth = true;
        extraConfig = ''
          # Nextcloud specific settings
          header {
            # Security headers
            X-Content-Type-Options nosniff
            X-Frame-Options DENY
            X-XSS-Protection "1; mode=block"
            Referrer-Policy "strict-origin-when-cross-origin"
          }
        '';
      };
      
      vaultwarden = {
        domain = "vault.${cfg.primaryDomain}";
        backend = "192.168.50.12";
        port = 80;
        enableAuth = true;
      };
      
      grafana = {
        domain = "grafana.${cfg.primaryDomain}";
        backend = "192.168.50.13";
        port = 3000;
        enableAuth = true;
      };
    };
  };
} 