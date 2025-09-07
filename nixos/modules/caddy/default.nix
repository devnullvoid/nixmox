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
          # Structured JSON logging for Alloy/Loki ingestion
          log {
            output file /var/log/caddy/caddy_main.log {
              roll_size 100MiB
              roll_keep 5
              roll_keep_for 100d
            }
            format json
            level INFO
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
              
              # Per-domain structured JSON logging
              log {
                output file /var/log/caddy/${service.domain}.log {
                  roll_size 100MiB
                  roll_keep 5
                  roll_keep_for 100d
                }
                format json
                level INFO
              }
              
              ${lib.optionalString (service.extraConfig != "") 
                service.extraConfig}
              
              # Basic reverse proxy configuration
              ${lib.optionalString (!(service.skipDefaultProxy or false)) ''
                reverse_proxy ${service.backend}:${toString service.port} {
                  header_up Host {host}
                  header_up X-Forwarded-Proto https
                  header_up X-Forwarded-Host {host}
                  header_up X-Forwarded-For {remote}
                  ${config.services.nixmox.caddyServiceConfigs.${name}.proxyConfig or ""}
                }
              ''}
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
                  
                  # Per-domain structured JSON logging
                  log {
                    output file /var/log/caddy/${proxy.domain}.log {
                      roll_size 100MiB
                      roll_keep 5
                      roll_keep_for 100d
                    }
                    format json
                    level INFO
                  }
                  
                  ${lib.optionalString (proxy.extraConfig != "") 
                    proxy.extraConfig}
                  
                  # Basic reverse proxy configuration
                  ${lib.optionalString (!(proxy.skipDefaultProxy or false)) ''
                    reverse_proxy ${proxy.upstream} {
                      header_up Host {host}
                      header_up X-Forwarded-Proto https
                      header_up X-Forwarded-Host {host}
                      header_up X-Forwarded-For {remote}
                      ${config.services.nixmox.caddyServiceConfigs.${serviceName}.proxyConfig or ""}
                    }
                  ''}
                }
              '') serviceConfig.proxies)
            )
          ) cfg.multiProxyServices)
        )}
      '';
      
      # Ensure reloads that expect /etc/caddy/Caddyfile succeed by providing a symlink
      # to the generated config in the Nix store.
      # Some tooling or manual `systemctl reload caddy` may trigger Caddy to read
      # from /etc/caddy/Caddyfile.
      # This keeps both start and reload paths consistent.

    };

    # Provide /etc/caddy/Caddyfile pointing at the generated config
    environment.etc."caddy/Caddyfile".source = config.services.caddy.configFile;

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
        ExecReload = mkForce "${pkgs.systemd}/bin/systemctl restart caddy.service";
      };
    };

    # Enable internal CA with wildcard private key (needed for HTTPS serving)
    services.nixmox.internalCa = mkIf cfg.internalCa.enable {
      enable = true;
      enableWildcardKey = cfg.internalCa.enableWildcardKey;
    };

    # Create Caddy log directory and ensure log files have correct permissions
    systemd.tmpfiles.rules = [
      "d /var/log/caddy 0755 caddy caddy"
      # Ensure log files are readable by Alloy (world read permission)
      "f /var/log/caddy/*.log 0644 caddy caddy"
    ];

    # Ensure Caddy user exists and has proper permissions
    users.users.caddy = {
      isSystemUser = true;
      group = "caddy";
      home = "/var/lib/caddy";
      createHome = true;
    };

    users.groups.caddy = {};

    # Caddy-specific Alloy configuration for log collection
    # This extends the common Alloy configuration without modifying it
    environment.etc."alloy/caddy.alloy" = mkIf config.services.nixmox.alloy.enable {
      source = pkgs.writeText "caddy-alloy.alloy" ''
        // Caddy-specific Alloy configuration for log collection
        
        // Loki client for Caddy log forwarding
        loki.write "caddy_loki" {
          endpoint {
            url = "http://${manifest.services.monitoring.ip or "192.168.99.18"}:3100/loki/api/v1/push"
          }
        }
        
        // Caddy log collection
        local.file_match "caddy_logs" {
          path_targets = [{"__path__" = "/var/log/caddy/*.log"}]
        }

        loki.source.file "caddy" {
          targets = local.file_match.caddy_logs.targets
          forward_to = [loki.relabel.caddy.receiver]
          tail_from_end = true
        }
        
        loki.relabel "caddy" {
          forward_to = [loki.write.caddy_loki.receiver]
          
          rule {
            target_label = "job"
            replacement = "caddy"
          }
          rule {
            target_label = "service"
            replacement = "caddy"
          }
          rule {
            target_label = "nodename"
            replacement = constants.hostname
          }
        }
      '';
      mode = "0644";
    };
  };
}
