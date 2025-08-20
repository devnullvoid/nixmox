{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.authentikIntegration;
in {
  options.services.nixmox.authentikIntegration = {
    enable = mkEnableOption "Authentik OAuth2 integration for services";

    # Authentik configuration
    authentik = {
      host = mkOption {
        type = types.str;
        default = "authentik.nixmox.lan";
        description = "Authentik host";
      };

      port = mkOption {
        type = types.int;
        default = 443;
        description = "Authentik port";
      };

      protocol = mkOption {
        type = types.enum [ "http" "https" ];
        default = "https";
        description = "Authentik protocol";
      };
    };

    # OAuth2 application configurations
    applications = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Application name";
          };

          clientId = mkOption {
            type = types.str;
            description = "OAuth2 client ID";
          };

          clientSecret = mkOption {
            type = types.str;
            description = "OAuth2 client secret (should be overridden via SOPS)";
          };

          redirectUris = mkOption {
            type = types.listOf types.str;
            description = "Allowed redirect URIs";
          };

          scopes = mkOption {
            type = types.listOf types.str;
            default = [ "openid" "profile" "email" ];
            description = "OAuth2 scopes to request";
          };
        };
      });
      default = {};
      description = "OAuth2 applications to configure";
    };
  };

  config = mkIf cfg.enable {
    # Default OAuth2 applications
    services.nixmox.authentikIntegration.applications = {
      nextcloud = {
        name = "Nextcloud";
        clientId = "nextcloud";
        clientSecret = "changeme"; # Should be overridden via SOPS
        redirectUris = [ "https://nextcloud.nixmox.lan/callback" ];
        scopes = [ "openid" "profile" "email" ];
      };

      jellyfin = {
        name = "Jellyfin";
        clientId = "jellyfin";
        clientSecret = "changeme"; # Should be overridden via SOPS
        redirectUris = [ "https://jellyfin.nixmox.lan/auth/callback" ];
        scopes = [ "openid" "profile" "email" ];
      };

      sonarr = {
        name = "Sonarr";
        clientId = "sonarr";
        clientSecret = "changeme"; # Should be overridden via SOPS
        redirectUris = [ "https://sonarr.nixmox.lan/auth/callback" ];
        scopes = [ "openid" "profile" "email" ];
      };

      radarr = {
        name = "Radarr";
        clientId = "radarr";
        clientSecret = "changeme"; # Should be overridden via SOPS
        redirectUris = [ "https://radarr.nixmox.lan/auth/callback" ];
        scopes = [ "openid" "profile" "email" ];
      };

      prowlarr = {
        name = "Prowlarr";
        clientId = "prowlarr";
        clientSecret = "changeme"; # Should be overridden via SOPS
        redirectUris = [ "https://prowlarr.nixmox.lan/auth/callback" ];
        scopes = [ "openid" "profile" "email" ];
      };
    };

    # Add host entries for Authentik
    networking.hosts = {
      "${cfg.authentik.host}" = [ "authentik.nixmox.lan" ];
    };

    # Environment variables for services to use
    environment.variables = {
      AUTHENTIK_HOST = cfg.authentik.host;
      AUTHENTIK_PORT = toString cfg.authentik.port;
      AUTHENTIK_PROTOCOL = cfg.authentik.protocol;
    };
  };
}
