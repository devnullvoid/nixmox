{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox;
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
        # Allow SSH
        allowedTCPPorts = [ 22 ];
        
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
    
    # Common users and groups
    users.users.nixmox = {
      isNormalUser = true;
      extraGroups = [ "wheel" "systemd-journal" ];
      # SSH keys - public keys don't need encryption
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkkp4yJcYNvDdzWfpHH5ZCeRrGRvL7fT18IJprgImVq jon@procyon"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDGV1JMc1cv8KrXdgXWrz5CwoKvNqZbVr7Mf4xLv7QJBcDiGeAOapgVPGHQ98Yzde+Yytrg65D66gPN8f/CVm+1nIsiLl4EEyzJ4WOQaDoiaNMfsfwpnZs5c5k15wwVMJyx/rLp6Q8ZZUl0drQ3m9BfKLHi+Y6DPNkmif9AE1GgXH0J+bYcWCjWhy67URcDQl8i6cmBYjnvbmpsbDEw+/chQ5LFutksIE9wZSyWRIHL5gmNQMJ/lP/iafRzWo/RuqJHdQio39qLzl2/r1shBU7T5zG/PBGltrpE1EVOsP42EdldGkdbgBHOu5nMKB4orc0dTEf24cA+tj2DwFOgVmHKMUO0YxSLJzoBJoc8im+ka0JhNpykPeoEjblrUtxAkWxVl8Z1Iaa1Uolx9+PeG7ZXAzRoXHa+deW6sYxZWMa52DLR/VZCA2JwVdHO0ZP4P4OLQlmVsw9Zjw2M9u68++3VIiAf0oV/IY81Fbg4527fvtRtdkQMVKcNmSBcQAANiPpBhL7RJ5gVz6e1P382+cV2c6ILe0pP8+MSs9/WLEGl6z9ftdJxyEl4I279+zFLAUsqmbcn47780c0c0xPGJU8NKY76H93jKt00wNqdFLmlWPLvAOXuURkjJIadwDRM7LrCzrxrGSoFRebiU9LNV4jsiq8PP0VaqTPyETpMQYUpd9w== jon@l33tbuntu"
      ];
      # Simple password for now - will use SOPS later
      # hashedPassword = "$6$rounds=5000$nixmox$changeme";
    };

    # Root user configuration for deployment
    users.users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkkp4yJcYNvDdzWfpHH5ZCeRrGRvL7fT18IJprgImVq jon@procyon"
      ];
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