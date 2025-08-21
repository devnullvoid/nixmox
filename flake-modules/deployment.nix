{ config, lib, inputs, ... }:

let
  # Helper function to generate for all supported systems
  forAllSystems = inputs.nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
  
  # Import nixpkgs for each system
  nixpkgsFor = forAllSystems (system: import inputs.nixpkgs {
    inherit system;
    overlays = [
      # Add any custom overlays here if needed
    ];
  });
in {
  # Deployment configuration
  perSystem = { config, pkgs, system, ... }: {
    # Deployment apps
    apps = {
      deploy-authentik = {
        type = "app";
        program = "${../scripts/deploy-authentik.sh}";
      };
      
      # Alternative deployment using direct nixos-rebuild
      deploy-authentik-direct = {
        type = "app";
        program = "${nixpkgsFor.${system}.nixos-rebuild}/bin/nixos-rebuild";
      };

      # Colmena deployment
      deploy-colmena = {
        type = "app";
        program = "${pkgs.colmena}/bin/colmena";
      };
    };
  };

  # Colmena configuration
  flake = {
    colmena = {
      # Meta configuration for all hosts
      meta = {
        nixpkgs = inputs.nixpkgs;
        specialArgs = {
          inherit inputs;
        };
      };

      # Define all our containers as hosts
      # Each container will be deployed as a separate NixOS host
      "caddy" = { name, nodes, ... }: {
        deployment = {
          targetHost = "caddy.nixmox.lan";
          targetUser = "root";
          # For local testing, we can use localhost
          # targetHost = "localhost";
        };
        imports = [
          ./containers.nix
        ];
        # Enable only the caddy container
        services.nixmox.caddy.enable = true;
      };

      "authentik" = { name, nodes, ... }: {
        deployment = {
          targetHost = "authentik.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.authentik.enable = true;
      };

      "postgresql" = { name, nodes, ... }: {
        deployment = {
          targetHost = "postgresql.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.postgresql.enable = true;
      };

      "nextcloud" = { name, nodes, ... }: {
        deployment = {
          targetHost = "nextcloud.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.nextcloud.enable = true;
      };

      "media" = { name, nodes, ... }: {
        deployment = {
          targetHost = "media.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.media.enable = true;
      };

      "monitoring" = { name, nodes, ... }: {
        deployment = {
          targetHost = "monitoring.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.monitoring.enable = true;
      };

      "guacamole" = { name, nodes, ... }: {
        deployment = {
          targetHost = "guacamole.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.guacamole.enable = true;
      };

      "vaultwarden" = { name, nodes, ... }: {
        deployment = {
          targetHost = "vaultwarden.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.vaultwarden.oci.enable = true;
      };

      "dns" = { name, nodes, ... }: {
        deployment = {
          targetHost = "dns.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.dns.enable = true;
      };

      "mail" = { name, nodes, ... }: {
        deployment = {
          targetHost = "mail.nixmox.lan";
          targetUser = "root";
        };
        imports = [
          ./containers.nix
        ];
        services.nixmox.mail.enable = true;
      };
    };
  };
}
