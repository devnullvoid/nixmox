{ config, pkgs, lib, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = cfg.domain or (network.domain or "nixmox.lan");
  
  # Get Authentik configuration from manifest
  authentikConfig = manifest.core_services.authentik or {};
  authentikDomain = cfg.authentikDomain or (authentikConfig.hostname or "authentik") + "." + baseDomain;
  authentikUpstream = cfg.authentikUpstream or (authentikConfig.ip or "192.168.99.12") + ":9000";
in {
  imports = [
    ./services.nix
    ../shared/internal-ca.nix
  ];

  options.services.nixmox.caddy = {
    enable = mkEnableOption "Caddy reverse proxy";

    # Global Caddy settings
    domain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Base domain for all services";
    };
    
    # Development mode (disable automatic HTTPS)
    # developmentMode = mkOption {
    #   type = types.bool;
    #   default = false;
    #   description = "Disable automatic HTTPS for development";
    # };

    # Internal CA configuration
    useInternalCa = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to use the NixMox internal CA";
    };
    
    caName = mkOption {
      type = types.str;
      default = "NixMox Internal CA";
      description = "Name for the internal CA";
    };

    # Enable internal CA with wildcard private key (needed for HTTPS serving)
    internalCa = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable internal CA with wildcard certificate";
      };
      
      enableWildcardKey = mkOption {
        type = types.bool;
        default = true;
        description = "Enable wildcard private key for HTTPS serving";
      };
    };



    # Authentik configuration
    # authentikDomain = mkOption {
    #   type = types.str;
    #   default = "authentik.nixmox.lan";
    #   description = "Authentik domain for forward auth";
    # };

    # authentikUpstream = mkOption {
    #   type = types.str;
    #   default = "authentik.nixmox.lan:9000";
    #   description = "Authentik upstream for forward auth";
    # };

    # Service definitions (legacy single-proxy format)
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
          
          skipDefaultProxy = mkOption {
            type = types.bool;
            default = false;
            description = "Skip the automatic reverse proxy configuration (use when handling proxying manually in extraConfig)";
          };
        };
      });
      default = {};
      description = "Services to proxy through Caddy (legacy format)";
    };

    # Multi-proxy service definitions (new format)
    multiProxyServices = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          proxies = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                domain = mkOption {
                  type = types.str;
                  description = "Domain for this proxy entry";
                };
                path = mkOption {
                  type = types.str;
                  default = "/";
                  description = "Path for this proxy entry";
                };
                upstream = mkOption {
                  type = types.str;
                  description = "Upstream backend (host:port)";
                };
                extraConfig = mkOption {
                  type = types.str;
                  default = "";
                  description = "Extra Caddy configuration for this proxy entry";
                };
                skipDefaultProxy = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Skip the automatic reverse proxy configuration";
                };
              };
            });
            description = "Multiple proxy configurations for this service";
          };
        };
      });
      default = {};
      description = "Services with multiple proxy configurations";
    };
  };

  config = mkIf cfg.enable {
    # Caddy service configuration
    services.caddy = {
      enable = true;
      
      # Use a custom Caddyfile instead of virtualHosts to avoid conflicts
      configFile = pkgs.writeText "Caddyfile" ''
        {
          admin 0.0.0.0:2019
          metrics {
            per_host
          }
          # Use our pre-generated wildcard certificate from SOPS secrets
          ${lib.optionalString cfg.useInternalCa ''
            # Note: Using SOPS-managed certificates
          ''}
        }
        
        # Legacy single-proxy services
        ${builtins.concatStringsSep "\n\n" (
          builtins.attrValues (builtins.mapAttrs (name: service: ''
            ${service.domain} {
              # Use our wildcard certificate for all services
              ${lib.optionalString cfg.useInternalCa 
                "tls /var/lib/shared-certs/wildcard-nixmox-lan.crt /var/lib/shared-certs/wildcard-nixmox-lan.key"}
              
              ${lib.optionalString (service.extraConfig != "") 
                service.extraConfig}
              
              # Basic reverse proxy configuration
              ${lib.optionalString (!(service.skipDefaultProxy or false)) "reverse_proxy ${service.backend}:${toString service.port}"}
            }
          '') cfg.services)
        )}
        
        # Multi-proxy services
        ${builtins.concatStringsSep "\n\n" (
          builtins.attrValues (builtins.mapAttrs (serviceName: serviceConfig:
            builtins.concatStringsSep "\n\n" (
              builtins.attrValues (builtins.mapAttrs (proxyName: proxy: ''
                ${proxy.domain} {
                  # Use our wildcard certificate for all services
                  ${lib.optionalString cfg.useInternalCa 
                    "tls /var/lib/shared-certs/wildcard-nixmox-lan.crt /var/lib/shared-certs/wildcard-nixmox-lan.key"}
                  
                  ${lib.optionalString (proxy.extraConfig != "") 
                    proxy.extraConfig}
                  
                  # Basic reverse proxy configuration
                  ${lib.optionalString (!(proxy.skipDefaultProxy or false)) "reverse_proxy ${proxy.upstream}"}
                }
              '') serviceConfig.proxies)
            )
          ) cfg.multiProxyServices)
        )}
      '';
      

    };

    # Basic firewall rules
    networking.firewall = {
      allowedTCPPorts = [
        80   # HTTP
        443  # HTTPS
        2019 # Caddy admin API (for metrics)
      ];
    };

    # Caddy Exporter for monitoring (commented out - not available in current NixOS)
    # services.prometheus.exporters.caddy = {
    #   enable = true;
    #   port = 2019;
    #   # Caddy metrics endpoint (from globalConfig above)
    #   caddyConfigPath = "/etc/caddy/caddy_config";
    # };



    # Systemd service configuration
    systemd.services.caddy = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Restart = mkForce "always";
        RestartSec = mkForce "10s";
        # Since admin is off, we need to restart instead of reload
        ExecReload = mkForce "/bin/systemctl restart caddy.service";
      };
    };

    # Enable internal CA with wildcard private key (needed for HTTPS serving)
    services.nixmox.internalCa = mkIf cfg.internalCa.enable {
      enable = true;
      enableWildcardKey = cfg.internalCa.enableWildcardKey;
    };


  };
}
