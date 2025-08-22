{ config, lib, pkgs, inputs, ... }:

with lib;

{
  # Common imports for all container hosts
  imports = [
    # Basic system configuration
    inputs.nixpkgs.nixosModules.notDetected
    
    # NixMox common configuration
    ./common/default.nix
    
    # SOPS secrets management
    inputs.sops-nix.nixosModules.sops
  ];

  # Common system configuration
  system.stateVersion = "25.11";
  
  # Basic boot configuration for containers
  boot = {
    # Use systemd-boot for containers
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    
    # Basic kernel modules
    kernelModules = [ "overlay" ];
    
    # Use tmpfs for /tmp
    tmp.useTmpfs = true;
  };
  
  # Basic file systems for containers
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
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

  # Enable systemd-resolved
  services.resolved.enable = true;

  # Common security settings
  security = {
    # Enable auditd
    auditd.enable = true;
    
    # Enable apparmor
    apparmor.enable = true;
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

  # Common tmpfiles rules
  systemd.tmpfiles.rules = [
    # Create common directories
    "d /var/lib/monitoring 0755 monitoring monitoring"
    "d /var/log/monitoring 0755 monitoring monitoring"
  ];
}
