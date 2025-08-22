{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
in {
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
      
      # Basic virtual host for now
      virtualHosts = {
        "${cfg.domain}" = {
          extraConfig = ''
            respond "NixMox Proxy - Service not found" 404
          '';
        };
      };
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
