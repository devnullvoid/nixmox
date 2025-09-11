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

  # Helper function to get service config from manifest
  getServiceConfig = serviceName: 
    manifest.services.${serviceName} or manifest.core_services.${serviceName} or {};
  
  # Helper function to build service proxy configuration
  mkServiceConfig = serviceName: serviceConfig:
    let
      # Get proxy configuration from manifest
      proxy = serviceConfig.interface.proxy or {};
      # Get authentication configuration from manifest
      auth = serviceConfig.interface.auth or {};
      
      # Check if this is a multi-proxy service (proxy is an attrset with multiple entries)
      isMultiProxy = proxy != {} && builtins.isAttrs proxy && !(proxy ? domain);
      
      # For single-proxy services, use the existing logic
      singleProxyResult = if !isMultiProxy then
        let
          # Determine auth modes based on manifest
          useForwardAuth = (auth.type or "") == "forward_auth";
          useOidc = (auth.type or "") == "oidc" && (auth.provider or "") == "authentik";
          
          # Parse upstream field to extract host and port
          parseUpstream = upstream:
            if upstream == "" then
              { host = serviceConfig.hostname; port = 80; }
            else
              let
                parts = lib.splitString ":" upstream;
                host = lib.head parts;
                port = if lib.length parts > 1 then lib.toInt (lib.elemAt parts 1) else 80;
              in
              { host = host; port = port; };
          
          upstreamInfo = parseUpstream (proxy.upstream or "");
          
          # Get backend from manifest (prefer proxy.upstream, fallback to hostname:port)
          backend = upstreamInfo.host;
          
          # Get domain from manifest
          domain = proxy.domain or "${serviceName}.${baseDomain}";
          
          # Get port from manifest (prefer parsed upstream port, fallback to proxy.port, then default to 80)
          port = upstreamInfo.port;
          
          # Determine if we should skip default proxy based on manifest path configuration
          skipDefaultProxy = (proxy.path or "/") != "/";
          
          # Resolve forward_auth upstream (defaults to authentik IP:9000 from manifest if available)
          authentikCore = manifest.core_services.authentik or {};
          forwardAuthUpstream = (auth.forward_auth_upstream or "http://${(authentikCore.ip or "")}${lib.optionalString (authentikCore ? ip) ":9000"}");
          
          # Common security headers for all services
          securityHeaders = ''
            # Security headers
            header {
              X-Content-Type-Options nosniff
              X-Frame-Options SAMEORIGIN
              X-XSS-Protection "1; mode=block"
              Referrer-Policy strict-origin-when-cross-origin
              # Remove server header
              -Server
            }
          '';
          
          # Generate extra config based on auth requirements
          extraConfig = if useForwardAuth then ''
            # Forward auth via Authentik (using embedded outpost)
            route {
              # Always forward outpost path to actual outpost
              reverse_proxy /outpost.goauthentik.io/* ${forwardAuthUpstream}
              
              # Forward authentication to outpost
              forward_auth ${forwardAuthUpstream} {
                uri /outpost.goauthentik.io/auth/caddy
                
                # Copy headers from Authentik (capitalization is important)
                copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Entitlements X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version
                
                # Trust private ranges (should probably be set to the outpost's IP)
                trusted_proxies private_ranges
              }
            }
            ${securityHeaders}
          '' else ''
            # Service without forward auth (OIDC or no auth)
            ${securityHeaders}
          '';
          
          # Add path-based routing for services that need it
          pathBasedRouting = if skipDefaultProxy && (proxy.path or "/") != "/" then ''
            # Handle path-based routing with redirect and proxy
            # Redirect root and non-service paths to the service path
            @notService {
              not path ${proxy.path}*
            }
            redir @notService ${proxy.path}
            
            # Proxy everything to upstream
            reverse_proxy ${backend}:${toString port} {
              flush_interval -1
            }
          '' else "";
          
          # Combine extra config with path-based routing
          finalExtraConfig = extraConfig + pathBasedRouting;
        in {
          domain = domain;
          backend = backend;
          port = port;
          enableAuth = useOidc || useForwardAuth;
          skipDefaultProxy = skipDefaultProxy;
          extraConfig = finalExtraConfig;
        }
      else null;
    in singleProxyResult;
  
  # Generate services configuration from manifest
  servicesConfig = builtins.mapAttrs mkServiceConfig (
    # Combine core services and application services
    (manifest.core_services or {}) // (manifest.services or {})
  );
  
  # Filter out null results (multi-proxy services)
  filteredServicesConfig = lib.filterAttrs (name: value: value != null) servicesConfig;
  
  # Generate multi-proxy services configuration
  multiProxyServicesConfig = builtins.mapAttrs (serviceName: serviceConfig:
    let
      proxy = serviceConfig.interface.proxy or {};
      
      # Check if this is a multi-proxy service
      isMultiProxy = proxy != {} && builtins.isAttrs proxy && !(proxy ? domain);
      
      # Parse upstream field to extract host and port
      parseUpstream = upstream:
        if upstream == "" then
          { host = serviceConfig.hostname; port = 80; }
        else
          let
            parts = lib.splitString ":" upstream;
            host = lib.head parts;
            port = if lib.length parts > 1 then lib.toInt (lib.elemAt parts 1) else 80;
          in
          { host = host; port = port; };
      
      # Generate proxy configurations for each entry
      proxyConfigs = if isMultiProxy then
        builtins.mapAttrs (proxyName: proxyEntry:
          let
            upstreamInfo = parseUpstream (proxyEntry.upstream or "");
            
            # Get service-specific Caddy configuration if available
            serviceCaddyConfig = config.services.nixmox.caddyServiceConfigs.${proxyName} or {};
            serviceExtraConfig = serviceCaddyConfig.extraConfig or "";
            
            # Get extra config from manifest
            manifestExtraConfig = proxyEntry.extra_config or "";
            
            # Get auth configuration from individual proxy entry
            proxyAuth = proxyEntry.auth or {};
            
            # Check if this service uses forward auth or OIDC
            useForwardAuth = (proxyAuth.type or "") == "forward_auth";
            useOidc = (proxyAuth.type or "") == "oidc";
            
            # Resolve forward_auth upstream (defaults to authentik IP:9000 from manifest if available)
            authentikCore = manifest.core_services.authentik or {};
            forwardAuthUpstream = (proxyAuth.forward_auth_upstream or "http://${(authentikCore.ip or "")}${lib.optionalString (authentikCore ? ip) ":9000"}");
            
            # Common security headers for all services
            securityHeaders = ''
              # Security headers
              header {
                X-Content-Type-Options nosniff
                X-Frame-Options SAMEORIGIN
                X-XSS-Protection "1; mode=block"
                Referrer-Policy strict-origin-when-cross-origin
                # Remove server header
                -Server
              }
            '';
            
            # Generate extra config based on auth requirements
            authExtraConfig = if useForwardAuth then ''
              # Forward auth via Authentik (using embedded outpost)
              route {
                # Always forward outpost path to actual outpost
                reverse_proxy /outpost.goauthentik.io/* ${forwardAuthUpstream}
                
                # Forward authentication to outpost
                forward_auth ${forwardAuthUpstream} {
                  uri /outpost.goauthentik.io/auth/caddy
                  
                  # Copy headers from Authentik (capitalization is important)
                  copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Entitlements X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version
                  
                  # Trust private ranges (should probably be set to the outpost's IP)
                  trusted_proxies private_ranges
                }
              }
              ${securityHeaders}
            '' else ''
              # Service without forward auth (OIDC or no auth)
              ${securityHeaders}
            '';
            
            # Combine manifest extra config with auth config
            combinedExtraConfig = manifestExtraConfig + authExtraConfig;
            
            # Use auth config if forward auth is enabled, otherwise use service-specific config, otherwise use combined config
            extraConfig = if useForwardAuth then authExtraConfig else if serviceExtraConfig != "" then serviceExtraConfig else combinedExtraConfig;
          in {
            domain = proxyEntry.domain;
            path = proxyEntry.path or "/";
            upstream = proxyEntry.upstream;
            extraConfig = extraConfig;
            skipDefaultProxy = false;
            # Pass through auth configuration
            auth = proxyEntry.auth or {};
          }
        ) proxy
      else {};
    in {
      proxies = proxyConfigs;
    }
  ) (
    # Only process services that have multi-proxy configurations
    lib.filterAttrs (serviceName: serviceConfig:
      let proxy = serviceConfig.interface.proxy or {};
      in proxy != {} && builtins.isAttrs proxy && !(proxy ? domain)
    ) (manifest.core_services or {}) // (manifest.services or {})
  );
in {
  imports = [
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
                auth = mkOption {
                  type = types.attrs;
                  default = {};
                  description = "Authentication configuration for this proxy entry";
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
    # Configure all services to be proxied through Caddy
    # Services are now generated from the manifest instead of hard-coded
    services.nixmox.caddy.services = filteredServicesConfig;
    
    # Configure multi-proxy services
    services.nixmox.caddy.multiProxyServices = multiProxyServicesConfig;

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
                    
                    ${proxy.extraConfig}
                    
                    # Basic reverse proxy configuration
                    ${lib.optionalString (!(proxy.skipDefaultProxy or false)) ''
                      reverse_proxy ${proxy.upstream} {
                        header_up Host {host}
                        header_up X-Forwarded-Proto https
                        header_up X-Forwarded-Host {host}
                        header_up X-Forwarded-For {remote}
                        ${config.services.nixmox.caddyServiceConfigs.${proxyName}.proxyConfig or ""}
                      }
                    ''}
                  }
                ''
              ) serviceConfig.proxies)
            )
          ) cfg.multiProxyServices)
        )}
      '';
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
