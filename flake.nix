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

    # Colmena for deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (top@{ config, withSystem, moduleWithSystem, ... }: {
      imports = [
        # Import flake modules for each major component
        ./flake-modules/development.nix
        ./flake-modules/deployment.nix
      ];

      # Define supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        # Core flake attributes
        description = "NixMox - NixOS LXC Orchestration on Proxmox";
        
        # Helper functions and configurations
        lib = {
          # Helper function to generate container images
          mkContainerImage = hostName: modules: inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "proxmox-lxc";
            modules = modules;
          };
        };

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
        };

        # Generate NixOS configurations for each host
        nixosConfigurations = {
          caddy = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/caddy.nix ];
            specialArgs = { inherit inputs; };
          };

          postgresql = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/postgresql.nix ];
            specialArgs = { inherit inputs; };
          };

          authentik = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/authentik.nix ];
            specialArgs = { inherit inputs; };
          };

          nextcloud = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/nextcloud.nix ];
            specialArgs = { inherit inputs; };
          };

          media = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/media.nix ];
            specialArgs = { inherit inputs; };
          };

          monitoring = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/monitoring.nix ];
            specialArgs = { inherit inputs; };
          };

          guacamole = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/guacamole.nix ];
            specialArgs = { inherit inputs; };
          };

          vaultwarden = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/vaultwarden.nix ];
            specialArgs = { inherit inputs; };
          };

          dns = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/dns.nix ];
            specialArgs = { inherit inputs; };
          };

          mail = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos/hosts/mail.nix ];
            specialArgs = { inherit inputs; };
          };
        };

        # Colmena deployment configuration
        colmenaHive = inputs.colmena.lib.makeHive {
          meta = {
            nixpkgs = import inputs.nixpkgs {
              system = "x86_64-linux";
            };
          };

          # Core infrastructure
          caddy = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "caddy.nixmox.lan";
              targetUser = "root";
              tags = [ "infra" "core" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.caddy._module.args.modules ];
          };

          postgresql = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "postgresql.nixmox.lan";
              targetUser = "root";
              tags = [ "infra" "database" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.postgresql._module.args.modules ];
          };

          authentik = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "authentik.nixmox.lan";
              targetUser = "root";
              tags = [ "infra" "auth" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.authentik._module.args.modules ];
          };

          dns = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "dns.nixmox.lan";
              targetUser = "root";
              tags = [ "infra" "core" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.dns._module.args.modules ];
          };

          # Application services
          nextcloud = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "nextcloud.nixmox.lan";
              targetUser = "root";
              tags = [ "services" "storage" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.nextcloud._module.args.modules ];
          };

          media = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "media.nixmox.lan";
              targetUser = "root";
              tags = [ "services" "media" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.media._module.args.modules ];
          };

          monitoring = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "monitoring.nixmox.lan";
              targetUser = "root";
              tags = [ "services" "monitoring" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.monitoring._module.args.modules ];
          };

          guacamole = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "guacamole.nixmox.lan";
              targetUser = "root";
              tags = [ "services" "remote" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.guacamole._module.args.modules ];
          };

          vaultwarden = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "vaultwarden.nixmox.lan";
              targetUser = "root";
              tags = [ "services" "security" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.vaultwarden._module.args.modules ];
          };

          mail = { name, nodes, pkgs, ... }: {
            deployment = {
              targetHost = "mail.nixmox.lan";
              targetUser = "root";
              tags = [ "services" "communication" ];
            };
            imports = [ inputs.self.outputs.nixosConfigurations.mail._module.args.modules ];
          };
        };

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