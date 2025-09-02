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
      # Import the service manifest
      _module.args.manifest = import ./nixos/service-manifest.nix;

      # Define supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        # Core flake attributes
        description = "NixMox - NixOS LXC Orchestration on Proxmox";
        
        # Reusable NixOS modules
        nixosModules = {
          core = import ./nixos/modules/core.nix;
          caddy = import ./nixos/modules/caddy;
          authentik = import ./nixos/modules/authentik;
          postgresql = import ./nixos/modules/postgresql;
          nextcloud = import ./nixos/modules/nextcloud;
          media = import ./nixos/modules/media;
          monitoring = import ./nixos/modules/monitoring;
          guacamole = import ./nixos/modules/guacamole;
          vaultwarden = import ./nixos/modules/vaultwarden;
          dns = import ./nixos/modules/dns;
          mail = import ./nixos/modules/mail;
          openbao = import ./nixos/modules/openbao;
          forgejo = import ./nixos/modules/forgejo;
        };

        # Dynamically generate NixOS configurations from manifest
        nixosConfigurations = let
          # Import the manifest
          manifest = import ./nixos/service-manifest.nix;
          
          # Helper function to create a NixOS configuration for a service
          mkServiceConfig = serviceName: serviceConfig: let
            # Base modules for all services
            baseModules = [
              (import ./nixos/hosts/nixmox-host.nix { inherit manifest; inherit serviceName; })
            ];
            
            # No special cases needed - OCI is now the default
            extraModules = [];
            
            # Combine base and extra modules
            allModules = baseModules ++ extraModules;
          in
            inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = allModules;
              specialArgs = { inherit inputs; inherit manifest; };
            };
          
          # Get all enabled services from manifest
          enabledServices = let
            allServices = (manifest.core_services or {}) // (manifest.services or {});
            enabledNames = builtins.attrNames (builtins.removeAttrs allServices 
              (builtins.filter (name: !(allServices.${name}.enable or false)) (builtins.attrNames allServices))
            );
          in
            builtins.listToAttrs (map (name: { inherit name; value = allServices.${name}; }) enabledNames);
          
        in
          # Generate configurations for all enabled services
          builtins.mapAttrs mkServiceConfig enabledServices;

        # Generate packages for container images
        packages = builtins.mapAttrs (system: nixpkgs: 
          builtins.mapAttrs (name: nixosConfig: 
            nixpkgs.runCommand "nixmox-${name}-lxc" {
              buildInputs = [ inputs.nixos-generators.packages.${system}.default nixpkgs.nix ];
            } ''
              ${inputs.nixos-generators.packages.${system}.default}/bin/nixos-generate -f proxmox-lxc -c ${nixosConfig.config.system.build.toplevel} -o $out
            ''
          ) (config.flake.nixosConfigurations or {})
        ) {
          x86_64-linux = import inputs.nixpkgs { system = "x86_64-linux"; };
          aarch64-linux = import inputs.nixpkgs { system = "aarch64-linux"; };
        };
      };
    });
} 