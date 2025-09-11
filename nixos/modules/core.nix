{ config, lib, pkgs, inputs, modulesPath, ... }:

with lib;

{
  # Common imports for all container hosts
  imports = [
    # Basic system configuration
    inputs.nixpkgs.nixosModules.notDetected
    
    # Proxmox LXC module for container-specific configurations
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    
    # NixMox common configuration
    ./common/default.nix
    
    # Network configuration
    ./network
    
    # SOPS secrets management
    inputs.sops-nix.nixosModules.sops
    
    # Internal CA certificate distribution
    ./shared/internal-ca.nix
  ];

  # NixMox service options
  options.services.nixmox = {
    domain = mkOption {
      type = types.str;
      default = "nixmox.lan";
      description = "Base domain for NixMox services";
    };

  };

  # Common configuration
  config = {
    # SOPS configuration
    sops.defaultSopsFile = ../../secrets/default.yaml;
    sops.age.keyFile = "/etc/age/keys.txt";
    
    # Common system configuration
    system.stateVersion = "25.11";
    
    # LXC-specific configuration
    proxmoxLXC = {
      manageNetwork = false;
      privileged = false;
    };
    
    # Nix settings for LXC containers
    nix.settings = { 
      sandbox = false; 
      experimental-features = [ "nix-command" "flakes" ];
    };
    
    # Allow unfree packages (needed for some proprietary software)
    nixpkgs.config.allowUnfree = true;
    
    # Basic boot configuration for containers
    boot = {
      # Minimal bootloader configuration for LXC containers
      loader.grub = {
        enable = false;
        device = "nodev";
      };
      
      # Basic kernel modules
      kernelModules = [ "overlay" ];
      
      # Use tmpfs for /tmp
      tmp.useTmpfs = true;
    };
    
    # Basic file systems for containers
    fileSystems = {
      # Root filesystem - minimal configuration for LXC containers
      "/" = {
        device = "none";
        fsType = "tmpfs";
        options = [ "defaults" "size=100%" ];
      };
      
      "/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "size=1G" "mode=1777" ];
      };
    };

    # Common networking configuration
    networking = {
      # Use systemd-resolved for DNS
      useDHCP = false;
      useNetworkd = true;
      
      # Enable IPv6
      enableIPv6 = true;
      
      # Use our internal DNS server as primary resolver (from network config)
      nameservers = [ config.services.nixmox.network.dns_server "8.8.8.8" "1.1.1.1" ];
      
      # Common firewall settings
      firewall = {
        enable = true;
        # Allow established connections
        allowedTCPPorts = [];
        allowedUDPPorts = [];
      };
    };

    # Common systemd configuration
    systemd = {
      # Enable systemd-networkd
      network.enable = true;
    };

    # Disable systemd-resolved in LXC containers (can conflict with other DNS services)
    services.resolved.enable = lib.mkForce false;
    
    # Manually configure DNS resolution to use our internal DNS server (from network config)
    environment.etc."resolv.conf".text = ''
      nameserver ${config.services.nixmox.network.dns_server}
      nameserver 8.8.8.8
      nameserver 1.1.1.1
      options timeout:2 attempts:3
    '';

    # Common security settings
    security = {
      # Disable auditd in LXC containers (not supported)
      auditd.enable = lib.mkForce false;
      
      # Disable apparmor in LXC containers (limited support)
      apparmor.enable = lib.mkForce false;
    };

    # Common system packages
    environment.systemPackages = with pkgs; [
      # Basic utilities
      vim
      curl
      wget
      htop
      iotop
      
      # Network tools
      iproute2
      netcat
      tcpdump
      
      # Monitoring tools
      lsof
      strace
      ltrace
    ];

    # Common users
    users.users = {
      # System user for monitoring
      monitoring = {
        isSystemUser = true;
        group = "monitoring";
        home = "/var/lib/monitoring";
        createHome = true;
      };
    };

    users.groups = {
      monitoring = {};
    };

    # Common systemd services
    systemd.services = {
      # Ensure network is ready before services start
      "network-online" = {
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-networkd-wait-online.service" ];
      };
    };

    # Enable internal CA certificate distribution for all hosts
    services.nixmox.internalCa = {
      enable = true;
      enableWildcardKey = true;  # Enable for HTTPS serving
    };

    # Common tmpfiles rules
    systemd.tmpfiles.rules = [
      # Create common directories
      "d /var/lib/monitoring 0755 monitoring monitoring"
      "d /var/log/monitoring 0755 monitoring monitoring"
    ];
  };
}
