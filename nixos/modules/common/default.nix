{ config, lib, pkgs, manifest, ... }:

with lib;

let
  cfg = config.services.nixmox;
  
  # Get monitoring service configuration from manifest
  monitoringService = manifest.services.monitoring or {};
  monitoringIP = monitoringService.ip or "192.168.99.18"; # Fallback IP
  
  # Get network configuration from manifest
  network = manifest.network or {};
  baseDomain = network.domain or "nixmox.lan";
in {
  options.services.nixmox = {
    enable = mkEnableOption "NixMox common services";
    
    internalNetwork = mkOption {
      type = types.str;
      default = "192.168.99.0/24";
      description = "Internal network CIDR";
    };
    
    gateway = mkOption {
      type = types.str;
      default = "192.168.99.1";
      description = "Gateway IP address";
    };
    
    # Grafana Agent (Alloy) configuration
    alloy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Grafana Agent (Alloy) for log collection to Loki";
      };
    };

    # SSH key configuration
    sshKeys = {
      nixmox = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "SSH authorized keys for nixmox user";
      };
      
      root = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "SSH authorized keys for root user";
      };
    };
  };

  config = mkIf cfg.enable {
    # Enable network configuration
    services.nixmox.network.enable = true;
    
    # Common system packages
environment.systemPackages = with pkgs; [
  # Basic utilities
  vim
  wget
  curl
  htop
  tmux
  
  # Development tools
  git
  
  # Monitoring tools
  prometheus-node-exporter
  
  # Network tools
  dig
  traceroute
  
  # Secrets management
  sops
  age
];
    
    # Common system settings
    system = {
      # Auto-upgrade (optional, can be disabled)
      autoUpgrade = {
        enable = false;
        dates = "02:00";
        flake = "github:devnullvoid/nixmox";
        allowReboot = false;
      };
      
      # State version for NixOS upgrades
      stateVersion = "25.11";
    };
    
    virtualisation = {
      containers.enable = true;
      oci-containers.backend = "podman";
      podman = {
        enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };

    # Common networking settings
    networking = {
      # DNS settings (use network configuration)
      nameservers = [ cfg.network.dns_server "8.8.8.8" "1.1.1.1" ];
      
      # Firewall common rules
      firewall = {
        # Allow SSH and Grafana Agent (Alloy) HTTP port for metrics (if enabled)
        allowedTCPPorts = [ 22 ] ++ lib.optional cfg.alloy.enable 12345;
        
        # Allow ICMP for ping
        allowedUDPPorts = [ ];
        
        # Trusted interfaces (for internal communication)
        trustedInterfaces = [ "eth0" ];
      };
    };
    
    # Common services
    services.openssh = {
      enable = true;
      settings = {
        # Security settings - temporarily allow root for deployment
        PermitRootLogin = "yes"; # Temporary for deployment
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
        
        # Performance settings
        MaxSessions = 10;
        MaxStartups = "10:30:60";
      };
      
      # Generate host keys if they don't exist
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
      ];
    };
    
    # Time synchronization
    services.timesyncd = {
      enable = true;
      servers = [ "time.cloudflare.com" "time.google.com" ];
    };
    
    # Node exporter for monitoring
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [
        "cpu"
        "diskstats"
        "filesystem"
        "loadavg"
        "meminfo"
        "netdev"
        "netstat"
        "textfile"
        "time"
        "vmstat"
        "logind"
        "systemd"
      ];
    };
    
        # Grafana Agent (Alloy) for log collection to Loki
    # IP addresses are derived from manifest.services.monitoring.ip
    services.alloy = mkIf cfg.alloy.enable {
      enable = true;
      extraFlags = [ "--server.http.listen-addr=0.0.0.0:12345" ];
    };
    
    # Alloy configuration file - logs collection only
    environment.etc."alloy/config.alloy" = mkIf cfg.alloy.enable {
      source = pkgs.writeText "alloy-config.alloy" ''
        // Alloy configuration for log collection only
        
        // Loki client for log forwarding
        loki.write "loki" {
          endpoint {
            url = "http://${monitoringIP}:3100/loki/api/v1/push"
          }
        }
        
        // Relabel rules for journal logs
        loki.relabel "journal" {
          forward_to = []
          
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label = "systemd_unit"
          }
          rule {
            source_labels = ["__journal__hostname"]
            target_label = "nodename"
          }
          rule {
            source_labels = ["__journal__syslog_identifier"]
            target_label = "syslog_identifier"
          }
        }
        
        // Systemd journal log collection
        loki.source.journal "journal" {
          forward_to = [loki.write.loki.receiver]
          max_age = "12h"
          labels = {
            job = "systemd-journal",
          }
          relabel_rules = loki.relabel.journal.rules
        }
      '';
      mode = "0644";
    };
    
    # Common users and groups
    users.users.nixmox = {
      isNormalUser = true;
      extraGroups = [ "wheel" "systemd-journal" ];
      # SSH keys from configuration
      openssh.authorizedKeys.keys = cfg.sshKeys.nixmox;
      # Simple password for now - will use SOPS later
      # hashedPassword = "$6$rounds=5000$nixmox$changeme";
      initialPassword = "nixmox";
    };
    


    # Root user configuration for deployment
    users.users.root = {
      openssh.authorizedKeys.keys = cfg.sshKeys.root;
    };
    
    # Allow wheel group to use sudo
    users.groups.wheel.members = [ "nixmox" ];
    
    # Security settings
    security = {
      # Allow wheel group to use sudo
      sudo.wheelNeedsPassword = false;
      
      # Audit settings
      auditd.enable = true;
    };
    
    # Logging configuration
    systemd.services.journald = {
      serviceConfig = {
        # Increase log storage
        SystemMaxUse = "1G";
        SystemKeepFree = "1G";
        
        # Compress logs
        Compress = true;
        
        # Forward to syslog if available
        ForwardToSyslog = false;
      };
    };
    
    # Common file systems
    fileSystems = {
      # Ensure /tmp is tmpfs
      "/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "size=1G" "mode=1777" ];
      };
    };
    

    
    # Systemd services
    systemd = {
      # Global settings
      services = {
        # Node exporter settings
        "prometheus-node-exporter" = {
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
        };
        

      };
      
      # Global targets
      targets = {
        # Ensure network is up before starting services
        "multi-user" = {
          requires = [ "network.target" ];
        };
      };
    };
  };
} 