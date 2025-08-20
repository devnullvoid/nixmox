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
  # Package configuration
  perSystem = { config, pkgs, system, ... }: {
    # Build container images using the nixosConfigurations from the flake
    packages = builtins.mapAttrs (name: nixosConfig: 
      nixpkgsFor.${system}.runCommand "nixmox-${name}-lxc" {
        buildInputs = [ inputs.nixos-generators.packages.${system}.default nixpkgsFor.${system}.nix ];
      } ''
        ${inputs.nixos-generators.packages.${system}.default}/bin/nixos-generate -f proxmox-lxc -c ${nixosConfig.config.system.build.toplevel} -o $out
      ''
    ) (config.flake.nixosConfigurations or {});
  };
}
