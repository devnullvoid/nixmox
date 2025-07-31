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
          # Let Proxmox manage network interfaces
          useDHCP = lib.mkForce false;
          useNetworkd = lib.mkForce false;
        };
        
        # Enable SSH for management
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = lib.mkForce "yes"; # Temporary for bootstrapping
            PasswordAuthentication = lib.mkForce true; # Temporary for bootstrapping
          };
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
          age.keyFile = "/etc/ssh/ssh_host_ed25519_key";
        };
      };
      
      # Container configurations
      containers = {
        # Authentik container
        authentik = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/authentik
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
          # Will be added in the mail module
        };
        
        # Media server container (Jellyfin + Arr stack)
        media = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/media
          ];
          
          networking.hostName = "media";
          
          # Media services
          services.jellyfin = {
            enable = true;
            # Configuration will be added in the media module
          };
        };
        
        # Nextcloud container
        nextcloud = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/nextcloud
          ];
          
          networking.hostName = "nextcloud";
          
          # Nextcloud configuration
          services.nextcloud = {
            enable = true;
            # Configuration will be added in the nextcloud module
          };
        };
        
        # Vaultwarden container
        vaultwarden = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/vaultwarden
          ];
          
          networking.hostName = "vaultwarden";
          
          # Vaultwarden configuration
          services.vaultwarden = {
            enable = true;
            # Configuration will be added in the vaultwarden module
          };
        };
        
        # DNS container (Unbound)
        dns = { config, pkgs, lib, ... }: {
          imports = [
            commonConfig
            ./modules/dns
          ];
          
          networking.hostName = "dns";
          
          # DNS configuration
          services.unbound = {
            enable = true;
            # Configuration will be added in the dns module
          };
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
            buildInputs = [ nixos-generators.packages.${system}.default ];
          } ''
            nixos-generators -f proxmox-lxc -c ${config} -o $out
          ''
        ) containers
      );
      
      # Helper functions
      lib = {
        inherit containers commonConfig;
      };
    };
} 