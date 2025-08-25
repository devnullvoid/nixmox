# Example: Integrating the NixMox Orchestrator with NixOS
# This shows how to use the orchestrator library in a real deployment

{ lib, config, pkgs, ... }:

let
  # Import our orchestrator library
  nixmoxLib = import ../lib { inherit lib config pkgs; };
  
  # Import our service manifest
  manifest = import ../nixos/service-manifest.nix;
  
  # Generate deployment configuration
  deploymentConfig = nixmoxLib.utils.generateDeploymentConfig manifest;
  
  # Extract key information
  validatedManifest = deploymentConfig.validated;
  deploymentPlan = deploymentConfig.plan;
  deploymentScripts = deploymentConfig.scripts;
  
  # Generate health check scripts for each service
  healthCheckScripts = lib.mapAttrs (serviceName: service:
    if lib.hasAttr "interface" service && 
       lib.hasAttr "health" service.interface then
      nixmoxLib.healthChecks.generateComprehensiveHealthCheck serviceName service.interface.health
    else
      null
  ) validatedManifest.services;
  
  # Generate Terraform configurations for each service
  terraformConfigs = lib.mapAttrs (serviceName: service:
    if lib.hasAttr "interface" service && 
       lib.hasAttr "terraform" service.interface then
      nixmoxLib.utils.generateServiceTerraform serviceName service validatedManifest
    else
      null
  ) validatedManifest.services;
  
  # Filter out null values
  validHealthChecks = lib.filterAttrs (name: value: value != null) healthCheckScripts;
  validTerraformConfigs = lib.filterAttrs (name: value: value != null) terraformConfigs;
  
in {
  # Example: Create a deployment configuration file
  environment.etc."nixmox-deployment-plan.json" = {
    text = builtins.toJSON {
      inherit (deploymentPlan) execution_order phases service_phases dependencies;
      timestamp = builtins.currentTime;
      version = "1.0.0";
    };
  };
  
  # Example: Create health check scripts
  environment.etc."nixmox-health-checks" = {
    source = pkgs.runCommand "nixmox-health-checks" {
      buildInputs = [ pkgs.bash ];
    } ''
      mkdir -p $out
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: script: ''
        cp ${script} $out/${name}-health-check.sh
        chmod +x $out/${name}-health-check.sh
      '') validHealthChecks)}
    '';
  };
  
  # Example: Create Terraform configuration directory
  environment.etc."nixmox-terraform" = {
    source = pkgs.runCommand "nixmox-terraform-configs" {
      buildInputs = [ pkgs.bash ];
    } ''
      mkdir -p $out
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: config: ''
        mkdir -p $out/${name}
        cp ${config.variablesFile} $out/${name}/terraform.tfvars
        cp ${config.initScript} $out/${name}/init.sh
        cp ${config.planScript} $out/${name}/plan.sh
        cp ${config.applyScript} $out/${name}/apply.sh
        chmod +x $out/${name}/*.sh
        echo "workspace = \"${config.workspaceName}\"" > $out/${name}/workspace.tf
      '') validTerraformConfigs)}
    '';
  };
  
  # Example: Create a systemd service for the orchestrator
  systemd.services.nixmox-orchestrator = {
    description = "NixMox Service Orchestrator";
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${deploymentConfig.mainScript}";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
  
  # Example: Create a timer for periodic health checks
  systemd.timers.nixmox-health-check = {
    description = "NixMox Service Health Check Timer";
    wantedBy = [ "timers.target" ];
    
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };
  
  systemd.services.nixmox-health-check = {
    description = "NixMox Service Health Check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "health-check-runner" ''
        #!/bin/bash
        set -euo pipefail
        
        echo "Running NixMox health checks..."
        
        # Run health checks for all services
        for script in /etc/nixmox-health-checks/*-health-check.sh; do
          if [ -f "$script" ]; then
            service_name=$(basename "$script" -health-check.sh)
            echo "Checking $service_name..."
            if "$script"; then
              echo "✓ $service_name is healthy"
            else
              echo "✗ $service_name health check failed"
            fi
          fi
        done
        
        echo "Health checks completed"
      '';
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
  
  # Example: Create a status command
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "nixmox-status" ''
      #!/bin/bash
      echo "NixMox Service Status"
      echo "====================="
      echo ""
      
      # Show deployment plan
      if [ -f /etc/nixmox-deployment-plan.json ]; then
        echo "Deployment Plan:"
        cat /etc/nixmox-deployment-plan.json | ${pkgs.jq}/bin/jq -r '.execution_order[]' | while read phase; do
          echo "  - $phase"
        done
        echo ""
      fi
      
      # Show service health
      echo "Service Health:"
      for script in /etc/nixmox-health-checks/*-health-check.sh; do
        if [ -f "$script" ]; then
          service_name=$(basename "$script" -health-check.sh)
          if "$script" > /dev/null 2>&1; then
            echo "  ✓ $service_name"
          else
            echo "  ✗ $service_name"
          fi
        fi
      done
    '')
    
    (writeShellScriptBin "nixmox-deploy" ''
      #!/bin/bash
      echo "NixMox Service Deployment"
      echo "========================="
      echo ""
      
      # This would trigger the orchestrator deployment
      echo "Starting deployment..."
      systemctl start nixmox-orchestrator
      
      echo "Deployment started. Check status with: nixmox-status"
    '')
  ];
}
