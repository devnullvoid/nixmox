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

      # Smart deployment with dependency resolution
      deploy-smart = {
        type = "app";
        program = "${../scripts/deploy-smart.sh}";
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

      # Define all our containers as hosts using existing NixOS configurations
      "caddy" = { name, nodes, ... }: {
        deployment = {
          targetHost = "caddy.nixmox.lan";
          targetUser = "root";
        };
        imports = [ ../nixos/hosts/caddy.nix ];
      };

      "postgresql" = { name, nodes, ... }: {
        deployment = {
          targetHost = "postgresql.nixmox.lan";
          targetUser = "root";
        };
        imports = [ ../nixos/hosts/postgresql.nix ];
      };

      "authentik" = { name, nodes, ... }: {
        deployment = {
          targetHost = "authentik.nixmox.lan";
          targetUser = "root";
          dependsOn = [ "postgresql" ]; # Authentik needs PostgreSQL
        };
        imports = [ ../nixos/hosts/authentik.nix ];
      };

      "dns" = { name, nodes, ... }: {
        deployment = {
          targetHost = "dns.nixmox.lan";
          targetUser = "root";
        };
        imports = [ ../nixos/hosts/dns.nix ];
      };

      "nextcloud" = { name, nodes, ... }: {
        deployment = {
          targetHost = "nextcloud.nixmox.lan";
          targetUser = "root";
          dependsOn = [ "postgresql" "caddy" ]; # Needs DB and reverse proxy
        };
        imports = [ ../nixos/hosts/nextcloud.nix ];
      };

      "media" = { name, nodes, ... }: {
        deployment = {
          targetHost = "media.nixmox.lan";
          targetUser = "root";
          dependsOn = [ "postgresql" "caddy" ]; # Needs DB and reverse proxy
        };
        imports = [ ../nixos/hosts/media.nix ];
      };

      "monitoring" = { name, nodes, ... }: {
        deployment = {
          targetHost = "monitoring.nixmox.lan";
          targetUser = "root";
          dependsOn = [ "postgresql" "caddy" ]; # Needs DB and reverse proxy
        };
        imports = [ ../nixos/hosts/monitoring.nix ];
      };

      "guacamole" = { name, nodes, ... }: {
        deployment = {
          targetHost = "guacamole.nixmox.lan";
          targetUser = "root";
          dependsOn = [ "postgresql" "caddy" ]; # Needs DB and reverse proxy
        };
        imports = [ ../nixos/hosts/guacamole.nix ];
      };

      "vaultwarden" = { name, nodes, ... }: {
        deployment = {
          targetHost = "vaultwarden.nixmox.lan";
          targetUser = "root";
          dependsOn = [ "caddy" ]; # Needs reverse proxy
        };
        imports = [ ../nixos/hosts/vaultwarden.nix ];
      };

      "mail" = { name, nodes, ... }: {
        deployment = {
          targetHost = "mail.nixmox.lan";
          targetUser = "root";
          dependsOn = [ "postgresql" "caddy" ]; # Needs DB and reverse proxy
        };
        imports = [ ../nixos/hosts/mail.nix ];
      };
    };
  };
}
