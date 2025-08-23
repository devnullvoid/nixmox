{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
in {
  imports = [
    ./services.nix
  ];

  options.services.nixmox.caddy = {
    enable = mkEnableOption "Caddy reverse proxy";

    # Global Caddy settings
    domain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Base domain for all services";
    };

    # Authentik configuration
    authentikDomain = mkOption {
      type = types.str;
      default = "authentik.nixmox.lan";
      description = "Authentik domain for forward auth";
    };

    authentikUpstream = mkOption {
      type = types.str;
      default = "authentik.nixmox.lan:9000";
      description = "Authentik upstream for forward auth";
    };

    # Service definitions
    services = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          domain = mkOption {
            type = types.str;
            description = "Domain for this service";
          };
          backend = mkOption {
            type = types.str;
            description = "Backend host for this service";
          };
          port = mkOption {
            type = types.int;
            description = "Backend port for this service";
          };
          enableAuth = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to enable Authentik forward auth";
          };
          extraConfig = mkOption {
            type = types.str;
            default = "";
            description = "Extra Caddy configuration for this service";
          };
        };
      });
      default = {};
      description = "Services to proxy through Caddy";
    };
  };

  config = mkIf cfg.enable {
    # Caddy service configuration
    services.caddy = {
      enable = true;
      
      # Global settings
      globalConfig = ''
        {
          admin off
          servers {
            metrics 127.0.0.1:9090
          }
        }
      '';
      
      # Use a custom Caddyfile instead of virtualHosts to avoid conflicts
      configFile = pkgs.writeText "Caddyfile" ''
        {
          admin off
          metrics 127.0.0.1:9090
        }
        
        ${builtins.concatStringsSep "\n\n" (
          builtins.attrValues (builtins.mapAttrs (name: service: ''
            ${service.domain} {
              ${service.extraConfig or ""}
              
              # Basic reverse proxy configuration
              reverse_proxy ${service.backend}:${toString service.port}
            }
          '') cfg.services)
        )}
      '';
      

    };

    # Basic firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        80   # HTTP
        443  # HTTPS
        9090 # Caddy metrics
      ];
    };

    # Systemd service configuration
    systemd.services.caddy = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Restart = mkForce "always";
        RestartSec = mkForce "10s";
      };
    };
  };
}
