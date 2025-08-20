{
  description = "NixMox - NixOS LXC Orchestration on Proxmox";

  inputs = {
    # Core Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Flake-parts for modularity
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs.follows = "nixpkgs";
    
    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Authentik integration
    authentik-nix = {
      url = "github:nix-community/authentik-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # NixOS generators for container images
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Terraform configuration
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (top@{ config, withSystem, moduleWithSystem, ... }: {
      imports = [
        # Import flake modules for each major component
        ./flake-modules/containers.nix
        ./flake-modules/development.nix
        ./flake-modules/deployment.nix
        ./flake-modules/packages.nix
      ];
      
      flake = {
        # Core flake attributes
        description = "NixMox - NixOS LXC Orchestration on Proxmox";
        
        # Helper functions and configurations
        lib = {
          inherit (config) containers commonConfig;
        };
        
        # Generate NixOS configurations for each container
        nixosConfigurations = builtins.mapAttrs (name: containerConfig: 
          inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              containerConfig
              {
                # Pass the flake inputs to the configuration
                _module.args = {
                  inherit (inputs) nixpkgs sops-nix authentik-nix nixos-generators;
                };
              }
              # Proxmox LXC module
              (import "${inputs.nixpkgs}/nixos/modules/virtualisation/proxmox-lxc.nix")
            ];
          }
        ) (config._module.args.containers or {});
      };
      
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      
      perSystem = { config, pkgs, system, ... }: {
        # System-specific configurations will be defined in the imported modules
      };
    });
} 