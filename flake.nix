{
  description = "NixMox - NixOS LXC Orchestration on Proxmox";

  inputs = {
    # Core Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
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
  };

  outputs = { self, nixpkgs, sops-nix, authentik-nix, nixos-generators }:
    let
      # System types we support
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      
      # Helper function to generate for all supported systems
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      # Import nixpkgs for each system
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        overlays = [
          # Add any custom overlays here if needed
        ];
      });
      
              # Common configuration for all containers
        commonConfig = { config, pkgs, lib, ... }: {
          imports = [
            # SOPS for secrets management
            sops-nix.nixosModules.sops
            
            # Common modules
            ./modules/common
          ];
        
        # Enable common services
        services.nixmox.enable = true;
        
        # Container-specific settings
        boot.isContainer = true;
        
        # Disable Nix sandboxing in containers (as recommended)
        nix.settings.sandbox = false;
        
        # Basic networking (Proxmox handles the actual network config)
networking = {
  firewall.enable = true;
  # Keep networking services enabled but let Proxmox manage the config
  useDHCP = lib.mkForce true;
  useNetworkd = lib.mkForce true;
};
        
        # Enable SSH for management
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = lib.mkForce "yes"; # Temporary for bootstrapping
            PasswordAuthentication = lib.mkForce true; # Temporary for bootstrapping
          };
        };

        # Configure root user with SSH keys
        users.users.root = {
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkkp4yJcYNvDdzWfpHH5ZCeRrGRvL7fT18IJprgImVq jon@procyon"
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDGV1JMc1cv8KrXdgXWrz5CwoKvNqZbVr7Mf4xLv7QJBcDiGeAOapgVPGHQ98Yzde+Yytrg65D66gPN8f/CVm+1nIsiLl4EEyzJ4WOQaDoiaNMfsfwpnZs5c5k15wwVMJyx/rLp6Q8ZZUl0drQ3m9BfKLHi+Y6DPNkmif9AE1GgXH0J+bYcWCjWhy67URcDQl8i6cmBYjnvbmpsbDEw+/chQ5LFutksIE9wZSyWRIHL5gmNQMJ/lP/iafRzWo/RuqJHdQio39qLzl2/r1shBU7T5zG/PBGltrpE1EVOsP42EdldGkdbgBHOu5nMKB4orc0dTEf24cA+tj2DwFOgVmHKMUO0YxSLJzoBJoc8im+ka0JhNpykPeoEjblrUtxAkWxVl8Z1Iaa1Uolx9+PeG7ZXAzRoXHa+deW6sYxZWMa52DLR/VZCA2JwVdHO0ZP4P4OLQlmVsw9Zjw2M9u68++3VIiAf0oV/IY81Fbg4527fvtRtdkQMVKcNmSBcQAANiPpBhL7RJ5gVz6e1P382+cV2c6ILe0pP8+MSs9/WLEGl6z9ftdJxyEl4I279+zFLAUsqmbcn47780c0xPGJU8NKY76H93jKt00wNqdFLmlWPLvAOXuURkjJIadwDRM7LrCzrxrGSoFRebiU9LNV4jsiq8PP0VaqTPyETpMQYUpd9w== jon@l33tbuntu"
          ];
        };
        
        # Create a basic user for management
        users.users.nixmox = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          initialPassword = "nixmox"; # Will be changed via secrets
        };
        
        # Enable basic services
        services = {
          # NTP for time sync
          timesyncd.enable = true;
          
          # Node exporter for monitoring
          prometheus.exporters.node.enable = true;
        };
        
        # SOPS configuration
sops = {
  defaultSopsFile = ./secrets/default.yaml;
  # age.keyFile will be set per-container or use default location
  # age.keyFile = "/path/to/age/key.txt";
  
  # SOPS secrets - temporarily disabled for testing
  # secrets.nixmox_password = {
  #   sopsFile = ./secrets/default.yaml;
  #   key = "nixmox.password";
  #   mode = "0400";
  # };
};
      };
      
      # Container configurations
      containers = {
        # Authentik container
        authentik = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/authentik
            authentik-nix.nixosModules.default
          ];
          
          networking.hostName = "authentik";
          
          # Authentik-specific settings
          services.nixmox.authentik.enable = true;
        };
        
        # Caddy reverse proxy container
        caddy = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/caddy
          ];
          
          networking.hostName = "caddy";
          
          # Caddy-specific settings
          services.caddy = {
            enable = true;
            # Configuration will be added in the caddy module
          };
        };
        
        # Monitoring container (Prometheus + Grafana)
        monitoring = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/monitoring
          ];
          
          networking.hostName = "monitoring";
          
          # Monitoring stack
          services.nixmox.monitoring.enable = true;
        };
        
        # Mail server container
        mail = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/mail
          ];
          
          networking.hostName = "mail";
          
          # Mail server configuration
          services.nixmox.mail.enable = true;
        };
        
        # Media server container (Jellyfin + Arr stack)
        media = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/media
          ];
          
          networking.hostName = "media";
          
          # Media services
          services.nixmox.media.enable = true;
        };
        
        # Nextcloud container
        nextcloud = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/nextcloud
          ];
          
          networking.hostName = "nextcloud";
          
          # Nextcloud configuration
          services.nixmox.nextcloud.enable = true;
        };
        
        # Vaultwarden container
        vaultwarden = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/vaultwarden
          ];
          
          networking.hostName = "vaultwarden";
          
          # Vaultwarden configuration
          services.nixmox.vaultwarden.enable = true;
        };
        
        # DNS container (Unbound)
        dns = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/dns
          ];
          
          networking.hostName = "dns";
          
          # DNS configuration
          services.nixmox.dns.enable = true;
        };
      };
      
      # Generate NixOS configurations for each container
      nixosConfigurations = builtins.mapAttrs (name: containerConfig: 
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            containerConfig
            {
                          # Pass the flake inputs to the configuration
            _module.args = {
              inherit nixpkgs sops-nix authentik-nix nixos-generators;
            };
            }
            # Proxmox LXC module
            (import "${nixpkgs}/nixos/modules/virtualisation/proxmox-lxc.nix")
          ];
        }
      ) containers;
      
    in {
      # NixOS configurations for each container
      inherit nixosConfigurations;
      
      # Development shell
      devShells = forAllSystems (system: {
        default = nixpkgsFor.${system}.mkShell {
          buildInputs = with nixpkgsFor.${system}; [
            # Development tools
            git
            nixos-generators.packages.${system}.default
            
            # Go for backend development
            go
            
            # Node.js for frontend development
            nodejs
            yarn
          ];
          
          shellHook = ''
            echo "Welcome to NixMox development environment!"
            echo "Available commands:"
            echo "  nix build .#nixosConfigurations.<container>.config.system.build.toplevel"
            echo "  nixos-generators -f proxmox-lxc -c ./configuration.nix"
          '';
        };
      });
      
      # Build container images
      packages = forAllSystems (system: 
        let
          pkgs = nixpkgsFor.${system};
        in
        builtins.mapAttrs (name: config: 
          pkgs.runCommand "nixmox-${name}-lxc" {
            buildInputs = [ nixos-generators.packages.${system}.default pkgs.nix ];
          } ''
            ${nixos-generators.packages.${system}.default}/bin/nixos-generate -f proxmox-lxc -c ${nixosConfigurations.${name}.config.system.build.toplevel} -o $out
          ''
        ) containers
      );
      
      # Helper functions
      lib = {
        inherit containers commonConfig;
      };
    };
} 