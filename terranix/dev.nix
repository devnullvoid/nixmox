{ lib, ... }:
{
  # Import the Proxmox LXC configuration
  imports = [ ./proxmox-lxc.nix ];

  # Development-specific overrides
  variable = {
    # Override defaults for development
    container_cpus = { default = 1; };
    container_memory = { default = 1024; };
    container_disk = { default = 4; };
    container_swap = { default = 256; };
  };

  # Development-specific outputs
  output = {
    development_info = {
      description = "Development environment information";
      value = {
        environment = "development";
        containers = [
          "caddy (10.10.0.10)"
          "postgresql (10.10.0.11)"
          "authentik (10.10.0.12)"
          "dns (10.10.0.13)"
        ];
        next_steps = [
          "1. Deploy base containers: just deploy-phase1 ENV=dev"
          "2. Build NixOS images: just build-images"
          "3. Deploy NixOS configurations: just deploy-phase2 ENV=dev"
        ];
      };
    };
  };
}
