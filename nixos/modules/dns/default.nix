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
      
      # Global settings
      settings = {
        server = {
          # Interface and port
          interface = [ "0.0.0.0" "::" ];
          port = "53";
          
          # Access control
          access-control = [
            "0.0.0.0/0 refuse"
            "127.0.0.0/8 allow"
            "192.168.50.0/24 allow"
            "10.0.0.0/8 allow"
            "172.16.0.0/12 allow"
          ];
          
          # Performance settings
          num-threads = "2";
          msg-cache-slabs = "4";
          rrset-cache-slabs = "4";
          infra-cache-slabs = "4";
          key-cache-slabs = "4";
          rrset-cache-size = "256k";
          msg-cache-size = "128k";
          so-rcvbuf = "1m";
          private-address = [
            "192.168.0.0/16"
            "169.254.0.0/16"
            "172.16.0.0/12"
            "10.0.0.0/8"
            "fd00::/8"
            "fe80::/10"
          ];
          
          # Security settings
          hide-identity = "yes";
          hide-version = "yes";
          harden-glue = "yes";
          harden-dnssec-stripped = "yes";
          harden-below-nxdomain = "yes";
          harden-referral-path = "yes";
          use-caps-for-id = "yes";
          
          # DNSSEC
          auto-trust-anchor-file = "/var/lib/unbound/root.key";
          trust-anchor = [
            "\".\" 20326 8 2 E06D44B80B8F1D39A95C0D0E4E041F15E4F915A5"
          ];
          
          # Forward zones for internal services
          local-zone = [
            "${cfg.primaryDomain} static"
          ];
        };
        
        # Forward zones
        forward-zone = [
          {
            name = ".";
            forward-addr = cfg.upstreamServers;
          }
        ];
        
        # Local data for internal services
        local-data = [
          # NS record for primary domain
          "${cfg.primaryDomain}. IN NS ${cfg.domain}."
        ] ++ (mapAttrsToList (name: service: 
          "${name}.${cfg.primaryDomain}. IN A ${service.ip}"
        ) cfg.services) ++ (concatLists (mapAttrsToList (name: service:
          map (alias: "${alias}.${cfg.primaryDomain}. IN CNAME ${name}.${cfg.primaryDomain}.") service.aliases
        ) cfg.services));
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
      # Core services
      authentik = {
        ip = "192.168.50.2";
        aliases = [ "auth" "identity" ];
      };
      
      caddy = {
        ip = "192.168.50.3";
        aliases = [ "proxy" "reverse-proxy" ];
      };
      
      monitoring = {
        ip = "192.168.50.4";
        aliases = [ "grafana" "prometheus" ];
      };
      
      mail = {
        ip = "192.168.50.5";
        aliases = [ "smtp" "imap" "mail" ];
      };
      
      media = {
        ip = "192.168.50.6";
        aliases = [ "jellyfin" "sonarr" "radarr" "prowlarr" ];
      };
      
      nextcloud = {
        ip = "192.168.50.7";
        aliases = [ "files" "cloud" ];
      };
      
      vaultwarden = {
        ip = "192.168.50.8";
        aliases = [ "vault" "passwords" ];
      };
      
      dns = {
        ip = "192.168.50.9";
        aliases = [ "ns" "nameserver" ];
      };
    };
  };
} 