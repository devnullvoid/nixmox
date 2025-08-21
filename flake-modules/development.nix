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
  # Development shell configuration
  perSystem = { config, pkgs, system, ... }: {
    # Development shell
    devShells.default = nixpkgsFor.${system}.mkShell {
      buildInputs = with nixpkgsFor.${system}; [
        # Development tools
        git
        inputs.nixos-generators.packages.${system}.default
        
        # Deployment tools
        colmena
        
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
  };
}
