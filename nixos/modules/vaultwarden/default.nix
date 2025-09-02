{ config, lib, pkgs, manifest, ... }:

with lib;

# Vaultwarden OCI Container Configuration (Default)
#
# This module configures Vaultwarden as an OCI container by default,
# which supports SSO integration with Authentik.
#
# The OCI module handles all the configuration including:
# - PostgreSQL database connection
# - Authentik SSO integration
# - Container management
# - SOPS secrets integration

{
  # Import the OCI module which contains all the configuration
  imports = [ ./oci.nix ];
  
  options.services.nixmox.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager (OCI container with SSO support)";
  };

  config = mkIf config.services.nixmox.vaultwarden.enable {
    # Enable OCI container when vaultwarden service is enabled
    services.nixmox.vaultwarden.oci.enable = true;
  };
} 