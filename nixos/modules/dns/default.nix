{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.dns;
in {
  options.services.nixmox.dns = {
    enable = mkEnableOption "DNS server (Unbound)";
    
    domain = mkOption {
      type = types.str;
      default = "dns.nixmox.lan";
      description = "Domain for DNS service";
    };
    
    primaryDomain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Primary domain for services";
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
        };
      });
      default = {};
      description = "Internal service DNS records";
    };
  };

  config = mkIf cfg.enable {
        # Unbound DNS server configuration
    services.unbound = {
      enable = true;
      
      # Use settings to directly configure Unbound based on NixOS Wiki example
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
          # Local zone for our primary domain
          local-zone = [ "${cfg.primaryDomain} static" ];
          # Local data entries - moved inside server block (simplified for now)
          local-data = [
            "${cfg.primaryDomain}. IN NS ${cfg.domain}."
          ] ++ (mapAttrsToList (name: service: 
            "${name}.${cfg.primaryDomain}. IN A ${service.ip}"
          ) cfg.services);
        };
        
        # Forward zone - must be an array as per NixOS Wiki example
        forward-zone = [
          {
            name = ".";
            forward-addr = cfg.upstreamServers;
          }
        ];
      };
    };
    
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
    
    # Default service configurations
    services.nixmox.dns.services = {
      # Core services (Phase 1)
      postgresql = {
        ip = "192.168.99.11";
        aliases = [ "db" "database" ];
      };
      
      caddy = {
        ip = "192.168.99.10";
        aliases = [ "proxy" "reverse-proxy" ];
      };
      
      dns = {
        ip = "192.168.99.13";
        aliases = [ "ns" "nameserver" ];
      };
      
      # Phase 2 services
      authentik = {
        ip = "192.168.99.12";
        aliases = [ "auth" "identity" ];
      };
      
      # Phase 3 services
      vaultwarden = {
        ip = "192.168.99.14";
        aliases = [ "vault" "passwords" ];
      };
      
      nextcloud = {
        ip = "192.168.99.15";
        aliases = [ "files" "cloud" ];
      };
      
      guacamole = {
        ip = "192.168.99.16";
        aliases = [ "remote" "rdp" ];
      };
      
      media = {
        ip = "192.168.99.17";
        aliases = [ "jellyfin" "sonarr" "radarr" "prowlarr" ];
      };
      
      monitoring = {
        ip = "192.168.99.18";
        aliases = [ "grafana" "prometheus" ];
      };
      
      mail = {
        ip = "192.168.99.19";
        aliases = [ "smtp" "imap" "mail" ];
      };
    };
  };
} 