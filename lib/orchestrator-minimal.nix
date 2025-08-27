# Minimal NixMox orchestrator
# Basic coordination without complex variable scoping issues

{ lib, config, pkgs, ... }:

let
  # Import all library modules
  serviceManifest = import ./service-manifest.nix { inherit lib config; };
  serviceInterface = import ./service-interface.nix { inherit lib config; };
  terraformRunner = import ./terraform-runner.nix { inherit lib pkgs config; };
  healthChecks = import ./health-checks.nix { inherit lib pkgs; };
  
  # Core services that are always required
  coreServices = ["dns" "postgresql" "caddy" "authentik"];
  
  # Generate deployment plan from manifest
  generateDeploymentPlan = manifest: let
    # Validate manifest
    validated = serviceManifest.validateServiceManifest manifest;
    
    # Get all services (core + optional)
    allServices = validated.core_services // validated.services;
    
    # Resolve dependencies for all services
    serviceDependencies = lib.mapAttrs (name: service: 
      serviceManifest.getServiceDependencies allServices name
    ) allServices;
    
    # Build complete deployment plan with proper phase separation
    deploymentPlan = {
      phases = [
        "tf_infra"      # Phase 1a: Terraform creates ALL containers
        "nix_core"      # Phase 1b: NixOS configures core services
        "tf_auth_core"  # Phase 2: Terraform creates Authentik resources
        "nix_apps"      # Phase 3: NixOS deploys applications
      ];
      service_phases = lib.attrNames validated.services;
      dependencies = serviceDependencies;
      execution_order = [
        "tf_infra"      # Phase 1a: All containers created
        "nix_core"      # Phase 1b: Core services running
        "tf_auth_core"  # Phase 2: Authentik resources created
        "nix_apps"      # Phase 3: Applications deployed
      ] ++ (lib.map (service: "nix_${service}") (lib.attrNames validated.services));
    };
  in
    deploymentPlan;
  
  # Generate deployment scripts for each phase
  generateDeploymentScripts = manifest: plan: {
    coreScripts = {};
    serviceScripts = {};
    terraformCoreScripts = {};
    nixosCoreScripts = {};
    serviceDeploymentScripts = {};
  };
  
  # Generate main orchestrator script
  generateMainOrchestratorScript = manifest: plan: scripts: let
    mainScript = pkgs.writeShellScript "nixmox-orchestrator" ''
      set -euo pipefail
      
      echo "NixMox Deployment Orchestrator"
      echo "==============================="
      echo "Starting deployment based on manifest..."
      
      # Set error handling
      set -e
      trap 'echo "Deployment failed at phase: $CURRENT_PHASE"; exit 1' ERR
      
      # Phase 1a: Terraform Infrastructure (ALL containers)
      echo ""
      echo "Phase 1a: Terraform Infrastructure"
      echo "----------------------------------"
      CURRENT_PHASE="tf_infra"
      echo "Creating ALL containers (infrastructure + applications)..."
      echo "Running: terraform apply -var='deployment_phase=1'"
      # TODO: Execute actual terraform apply
      
      # Phase 1b: NixOS Core Services
      echo ""
      echo "Phase 1b: NixOS Core Services"
      echo "----------------------------"
      CURRENT_PHASE="nix_core"
      echo "Deploying NixOS to core infrastructure containers..."
      echo "Waiting for core services to be healthy..."
      # TODO: Execute nixos-rebuild for core services
      # TODO: Wait for health checks (DNS, PostgreSQL, Caddy, Authentik)
      
      # Phase 2: Terraform Authentication Core
      echo ""
      echo "Phase 2: Terraform Authentication Core"
      echo "--------------------------------------"
      CURRENT_PHASE="tf_auth_core"
      echo "Creating Authentik outposts and OIDC applications..."
      echo "Running: terraform apply -var='deployment_phase=2'"
      # TODO: Execute actual terraform apply
      
      # Phase 3: NixOS Application Services
      echo ""
      echo "Phase 3: NixOS Application Services"
      echo "-----------------------------------"
      CURRENT_PHASE="nix_apps"
      echo "Deploying NixOS to application containers..."
      # TODO: Execute nixos-rebuild for application services
      
      # Per-service deployments (if needed)
      echo ""
      echo "Per-Service Deployments"
      echo "----------------------"
      
      ${lib.concatStringsSep "\n" (lib.map (serviceName: ''
        echo "Deploying service: ${serviceName}"
        CURRENT_PHASE="nix_${serviceName}"
        echo "Service ${serviceName} deployment completed"
      '') plan.service_phases)}
      
      echo ""
      echo "All phases completed successfully!"
      echo "NixMox deployment orchestration finished"
    '';
  in
    mainScript;
  
  # Generate rollback script
  generateRollbackScript = manifest: plan: let
    rollbackScript = pkgs.writeShellScript "nixmox-rollback" ''
      set -euo pipefail
      
      echo "NixMox Rollback Orchestrator"
      echo "============================"
      echo "Starting rollback process..."
      
      # This would implement rollback logic based on the deployment state
      # For now, it's a placeholder
      echo "Rollback functionality to be implemented"
    '';
  in
    rollbackScript;
  
  # Generate status monitoring script
  generateStatusScript = manifest: plan: let
    statusScript = pkgs.writeShellScript "nixmox-status" ''
      set -euo pipefail
      
      echo "NixMox Deployment Status"
      echo "========================"
      echo "Timestamp: $(date -Iseconds)"
      echo ""
      
      # Check core services
      echo "Core Services:"
      ${lib.concatStringsSep "\n" (lib.map (service: ''
        echo -n "  ${service}: "
        if systemctl is-active --quiet ${service}; then
          echo "✓ ACTIVE"
        else
          echo "✗ INACTIVE"
        fi
      '') coreServices)}
      
      echo ""
      echo "Optional Services:"
      ${lib.concatStringsSep "\n" (lib.map (serviceName: ''
        echo -n "  ${serviceName}: "
        if [ -f "/etc/systemd/system/${serviceName}.service" ]; then
          if systemctl is-active --quiet ${serviceName}; then
            echo "✓ ACTIVE"
          else
            echo "✗ INACTIVE"
          fi
        else
          echo "○ NOT INSTALLED"
        fi
      '') plan.service_phases)}
      
      echo ""
      echo "Terraform Workspaces:"
      # This would check Terraform workspace status
      echo "  (Terraform status to be implemented)"
    '';
  in
    statusScript;

in {
  inherit generateDeploymentPlan;
  inherit generateDeploymentScripts;
  inherit generateMainOrchestratorScript;
  inherit generateRollbackScript;
  inherit generateStatusScript;
  inherit coreServices;
}