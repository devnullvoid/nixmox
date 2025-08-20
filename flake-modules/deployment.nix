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
    };
  };
}
