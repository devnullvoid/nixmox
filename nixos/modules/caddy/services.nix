# Caddy service definitions for the dedicated reverse proxy container
# This file defines all the services that Caddy will proxy to other containers
# Services are now configured from the manifest instead of hard-coded values

{ config, pkgs, lib, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.caddy;
  baseDomain = cfg.domain;
  
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
      # Get health configuration from manifest
      health = serviceConfig.interface.health or {};
      
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
      forwardAuthUpstream = (auth.forward_auth_upstream or "${(authentikCore.ip or "")}${lib.optionalString (authentikCore ? ip) ":9000"}");
      
      # Generate extra config based on auth requirements
      extraConfig = if useForwardAuth then ''
        # Forward auth via Authentik
        header {
          # Security headers
          X-Content-Type-Options nosniff
          X-Frame-Options SAMEORIGIN
          X-XSS-Protection "1; mode=block"
          Referrer-Policy strict-origin-when-cross-origin
          # Remove server header
          -Server
        }
        
        forward_auth ${forwardAuthUpstream} {
          except /health /metrics /alive
        }
      '' else if useOidc then ''
        # OIDC authentication - let the backend service handle OIDC
        header {
          # Security headers
          X-Content-Type-Options nosniff
          X-Frame-Options SAMEORIGIN
          X-XSS-Protection "1; mode=block"
          Referrer-Policy strict-origin-when-cross-origin
          # Remove server header
          -Server
        }
      '' else ''
        # Service without authentication
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
    in {
      domain = domain;
      backend = backend;
      port = port;
      enableAuth = useOidc || useForwardAuth;
      skipDefaultProxy = skipDefaultProxy;
      extraConfig = extraConfig;
    };
  
  # Generate services configuration from manifest
  servicesConfig = builtins.mapAttrs mkServiceConfig (
    # Combine core services and application services
    (manifest.core_services or {}) // (manifest.services or {})
  );
in {
  config = mkIf cfg.enable {
    # Configure all services to be proxied through Caddy
    # Services are now generated from the manifest instead of hard-coded
    services.nixmox.caddy.services = servicesConfig;
  };
}
