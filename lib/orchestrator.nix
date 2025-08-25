# Main NixMox orchestrator
# Coordinates Terraform and NixOS deployments based on manifest

{ lib, config, pkgs, ... }:

let
  # Import all library modules
  serviceManifest = import ./service-manifest.nix { inherit lib config; };
  serviceInterface = import ./service-interface.nix { inherit lib config; };
  terraformRunner = import ./terraform-runner.nix { inherit lib pkgs config; };
  healthChecks = import ./health-checks.nix { inherit lib pkgs; };
  
  # Core services that are always required
  coreServices = ["dns" "postgresql" "caddy" "authentik"];
  
  # Phase definitions
  phases = {
    tf_infra = {
      name = "Terraform Infrastructure";
      description = "Provision core infrastructure primitives";
      services = [];
      terraform = true;
      nixos = false;
    };
    
    nix_core = {
      name = "NixOS Core Services";
      description = "Configure core NixOS services";
      services = coreServices;
      terraform = false;
      nixos = true;
    };
    
    tf_auth_core = {
      name = "Terraform Authentication Core";
      description = "Provision Authentik resources";
      services = [];
      terraform = true;
      nixos = false;
    };
  };
  
  # Generate deployment plan from manifest
  generateDeploymentPlan = manifest: let
    # Validate manifest
    validated = serviceManifest.validateServiceManifest manifest;
    
    # Get all services (core + optional)
    allServices = manifest.core_services // manifest.services;
    
    # Resolve dependencies for all services
    serviceDependencies = lib.mapAttrs (name: service: 
      serviceManifest.getServiceDependencies allServices name
    ) allServices;
    
    # Generate service deployment phases
    servicePhases = lib.mapAttrs (name: service: {
      inherit name;
      terraform_infra = {
        name = "Terraform Service Infrastructure";
        description = "Provision service infrastructure";
        terraform = true;
        nixos = false;
        depends_on = serviceDependencies.${name};
      };
      
      nixos_config = {
        name = "NixOS Service Configuration";
        description = "Configure service on NixOS";
        terraform = false;
        nixos = true;
        depends_on = ["terraform_infra"];
      };
      
      terraform_config = {
        name = "Terraform Service Configuration";
        description = "Apply service-specific Terraform";
        terraform = true;
        nixos = false;
        depends_on = ["nixos_config"];
      };
      
      verify = {
        name = "Service Verification";
        description = "Verify service health and connectivity";
        terraform = false;
        nixos = false;
        depends_on = ["terraform_config"];
      };
    }) manifest.services;
    
    # Build complete deployment plan
    deploymentPlan = {
      phases = phases;
      service_phases = servicePhases;
      dependencies = serviceDependencies;
      execution_order = generateExecutionOrder phases servicePhases;
    };
  in
    deploymentPlan;
  
  # Generate execution order based on dependencies
  generateExecutionOrder = phases: servicePhases: let
    # Start with core phases
    coreOrder = [
      "tf_infra"
      "nix_core"
      "tf_auth_core"
    ];
    
    # Generate service execution order
    serviceOrder = lib.concatLists (lib.mapAttrs (serviceName: phases) servicePhases);
    
    # Combine core and service phases
    allPhases = coreOrder ++ serviceOrder;
  in
    allPhases;
  
  # Generate deployment scripts for each phase
  generateDeploymentScripts = manifest: plan: let
    # Core phase scripts
    coreScripts = lib.mapAttrs (phaseName: phase) plan.phases;
    
    # Service phase scripts
    serviceScripts = lib.mapAttrs (serviceName: servicePhases) plan.service_phases;
    
    # Generate Terraform scripts for core phases
    terraformCoreScripts = lib.mapAttrs (phaseName: phase) (lib.filterAttrs (name: phase: phase.terraform) plan.phases);
    
    # Generate NixOS scripts for core phases
    nixosCoreScripts = lib.mapAttrs (phaseName: phase) (lib.filterAttrs (name: phase: phase.nixos) plan.phases);
    
    # Generate service scripts
    serviceDeploymentScripts = lib.mapAttrs (serviceName: servicePhases) plan.service_phases;
  in
    {
      inherit coreScripts;
      inherit serviceScripts;
      inherit terraformCoreScripts;
      inherit nixosCoreScripts;
      inherit serviceDeploymentScripts;
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
      
      # Phase 1: Terraform Infrastructure
      echo ""
      echo "Phase 1: Terraform Infrastructure"
      echo "---------------------------------"
      CURRENT_PHASE="tf_infra"
      
      if [ -f "${scripts.terraformCoreScripts.tf_infra}"]; then
        echo "Running Terraform infrastructure setup..."
        ${scripts.terraformCoreScripts.tf_infra}
      else
        echo "No Terraform infrastructure setup required"
      fi
      
      # Phase 2: NixOS Core Services
      echo ""
      echo "Phase 2: NixOS Core Services"
      echo "----------------------------"
      CURRENT_PHASE="nix_core"
      
      if [ -f "${scripts.nixosCoreScripts.nix_core}"]; then
        echo "Deploying NixOS core services..."
        ${scripts.nixosCoreScripts.nix_core}
      else
        echo "No NixOS core deployment required"
      fi
      
      # Phase 3: Terraform Authentication Core
      echo ""
      echo "Phase 3: Terraform Authentication Core"
      echo "--------------------------------------"
      CURRENT_PHASE="tf_auth_core"
      
      if [ -f "${scripts.terraformCoreScripts.tf_auth_core}"]; then
        echo "Setting up authentication resources..."
        ${scripts.terraformCoreScripts.tf_auth_core}
      else
        echo "No authentication setup required"
      fi
      
      # Phase 4+: Service Deployments
      echo ""
      echo "Phase 4+: Service Deployments"
      echo "-----------------------------"
      
      ${lib.concatStringsSep "\n" (lib.mapAttrs (serviceName: servicePhases: ''
        echo "Deploying service: ${serviceName}"
        CURRENT_PHASE="${serviceName}"
        
        # Terraform Service Infrastructure
        if [ -f "${servicePhases.terraform_infra}"]; then
          echo "  - Terraform infrastructure..."
          ${servicePhases.terraform_infra}
        fi
        
        # NixOS Service Configuration
        if [ -f "${servicePhases.nixos_config}"]; then
          echo "  - NixOS configuration..."
          ${servicePhases.nixos_config}
        fi
        
        # Terraform Service Configuration
        if [ -f "${servicePhases.terraform_config}"]; then
          echo "  - Terraform configuration..."
          ${servicePhases.terraform_config}
        fi
        
        # Service Verification
        if [ -f "${servicePhases.verify}"]; then
          echo "  - Verifying service..."
          ${servicePhases.verify}
        fi
        
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
      ${lib.concatStringsSep "\n" (lib.mapAttrs (name: service: ''
        echo -n "  ${name}: "
        if [ -f "/etc/systemd/system/${name}.service" ]; then
          if systemctl is-active --quiet ${name}; then
            echo "✓ ACTIVE"
          else
            echo "✗ INACTIVE"
          fi
        else
          echo "○ NOT INSTALLED"
        fi
      '') manifest.services)}
      
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
  inherit phases;
  inherit coreServices;
}