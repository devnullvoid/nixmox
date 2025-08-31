{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox.dns;
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
  
  # Get all services from manifest (core + application services)
  allServices = (manifest.core_services or {}) // (manifest.services or {});
  
  # Generate DNS records from manifest services
  # Create both hostname A records and service CNAME records
  manifestServices = builtins.mapAttrs (serviceName: serviceConfig:
    let
      # Use the service's hostname for A record (e.g., "vaultwarden.nixmox.lan")
      # The hostname should already include the full domain, so don't add domain suffix
      hostname = serviceConfig.hostname or serviceName;
      ip = serviceConfig.ip or "127.0.0.1";

      # Extract service domain from proxy.domain for CNAME record (e.g., "vault.nixmox.lan")
      serviceDomain = serviceConfig.interface.proxy.domain or null;

      # Create aliases list - if service domain exists and differs from hostname, add CNAME
      # Store just the subdomain part (e.g., "vault" from "vault.nixmox.lan")
      aliases = if serviceDomain != null && serviceDomain != hostname then
        let
          # Extract subdomain (remove domain suffix)
          subdomain = builtins.head (builtins.split "\\." serviceDomain);
        in
        [ subdomain ]
      else
        [];
    in
    {
      inherit ip aliases hostname;
      domain = hostname;  # The primary domain for this service
    }
  ) allServices;
  
  # Merge manifest services with manual overrides (manual takes precedence)
  finalServices = manifestServices // cfg.services;
in {
  options.services.nixmox.dns = {
    enable = mkEnableOption "DNS server (Unbound)";
    
    domain = mkOption {
      type = types.str;
      default = "";
      description = "Domain for DNS service; if empty, uses manifest value or default";
    };
    
    primaryDomain = mkOption {
      type = types.str;
      default = "";
      description = "Primary domain for services; if empty, uses manifest value or default";
    };
    
    upstreamServers = mkOption {
      type = types.listOf types.str;
      default = [
        "1.1.1.1"
        "1.0.0.1"
        "8.8.8.8"
        "8.8.4.4"
      ];
      description = "Upstream DNS servers";
    };
    
    # Service records for internal services
    # These can override manifest values if needed
    services = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          ip = mkOption {
            type = types.str;
            description = "IP address for this service";
          };
          aliases = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Additional aliases for this service";
          };
          domain = mkOption {
            type = types.str;
            description = "Full domain name for this service";
          };
        };
      });
      default = {};
      description = "Internal service DNS records (can override manifest values)";
    };
  };

  config = mkIf cfg.enable {
    # Use manifest values with fallbacks to manual configuration
    services.nixmox.dns.domain = mkDefault (manifest.core_services.dns.hostname or "dns.${baseDomain}");
    services.nixmox.dns.primaryDomain = mkDefault baseDomain;
    
    # Unbound DNS server configuration - minimal for debugging
    services.unbound = {
      enable = true;
      
      # Use settings to directly configure Unbound
      settings = {
        # Server configuration
        server = {
          interface = [ "0.0.0.0" "::" ];
          port = "53";
          access-control = [
            "0.0.0.0/0 refuse"
            "127.0.0.0/8 allow"
            "192.168.99.0/24 allow"
            "10.0.0.0/8 allow"
            "172.16.0.0/12 allow"
          ];
          num-threads = "2";
          msg-cache-size = "128k";
          rrset-cache-size = "256k";
          hide-identity = "yes";
          hide-version = "yes";
          harden-glue = "yes";
          harden-dnssec-stripped = "yes";
          harden-below-nxdomain = "yes";
          harden-referral-path = "yes";
          use-caps-for-id = "yes";
          auto-trust-anchor-file = "/var/lib/unbound/root.key";
          
          private-domain: "${cfg.primaryDomain}";
          
          # Local zone for our primary domain  
          local-zone = [ "${cfg.primaryDomain} static" ];
          
          # Local data entries - generate from manifest services
          local-data = [
            "\"${cfg.primaryDomain}. NS ${cfg.domain}.\""
          ] ++ (mapAttrsToList (name: service:
            # Only add domain suffix if hostname doesn't already contain a dot (full domain)
            let
              fullHostname = if builtins.match ".*\\..*" service.hostname != null
                then service.hostname
                else "${service.hostname}.${cfg.primaryDomain}";
            in
            "\"${fullHostname}. A ${service.ip}\""
          ) finalServices) ++ (concatLists (mapAttrsToList (name: service:
            # For auth service, return A record directly to avoid CNAME resolution issues
            map (alias:
              if alias == "auth" then
                "\"${alias}.${cfg.primaryDomain}. A 192.168.99.10\""
              else
                "\"${alias}.${cfg.primaryDomain}. CNAME caddy.${cfg.primaryDomain}.\""
            ) service.aliases
          ) finalServices));
        };
        
        # Forward zone - minimal configuration
        forward-zone = [
          {
            name = ".";
            forward-addr = cfg.upstreamServers;
          }
        ];
      };
    };
    
    # Disable systemd-resolve to avoid port conflict with Unbound
    services.resolved.enable = lib.mkForce false;
    
    # Firewall rules for DNS
    networking.firewall = {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
    };
    
    # Systemd service configuration
    systemd.services.unbound = {
      # Ensure Unbound starts after network
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      # Service configuration
      serviceConfig = {
        # User and group
        User = "unbound";
        Group = "unbound";
        
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
    
    # Health check for Unbound
    systemd.services.unbound-health = {
      description = "Unbound DNS health check";
      wantedBy = [ "multi-user.target" ];
      after = [ "unbound.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.dnsutils}/bin/dig @127.0.0.1 ${cfg.primaryDomain}";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
    # Create Unbound user
    users.users.unbound = {
      isSystemUser = true;
      group = "unbound";
      home = "/var/lib/unbound";
      createHome = true;
    };
    
    users.groups.unbound = {};
  };
} 