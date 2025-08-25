# NixMox library functions
# Main entry point for all library modules

{ lib, config, pkgs, ... }:

let
  # Import all library modules
  serviceManifest = import ./service-manifest.nix { inherit lib config; };
  serviceInterface = import ./service-interface.nix { inherit lib config; };
  terraformRunner = import ./terraform-runner-basic.nix { inherit lib pkgs config; };
  healthChecks = import ./health-checks-fixed.nix { inherit lib pkgs; };
  orchestrator = import ./orchestrator-minimal.nix { inherit lib config pkgs; };
  
  # Combine all library functions
  nixmoxLib = {
    # Service manifest functions
    inherit (serviceManifest)
      serviceManifestSchema
      validateServiceManifest
      getServiceDependencies
      getDeploymentOrder
      mkService;
    
    # Service interface functions
    inherit (serviceInterface)
      serviceInterfaceSchema
      validateServiceInterface;
    
    # Terraform runner functions
    inherit (terraformRunner)
      terraformRunnerConfig
      generateWorkspaceName
      generateTerraformVariables
      generateTerraformVariablesFile
      generateTerraformInitScript
      generateTerraformPlanScript
      generateTerraformApplyScript
      generateTerraformOutputScript
      checkTerraformChanges;
    
    # Health check functions
    inherit (healthChecks)
      healthCheckPatterns
      generateHealthCheck
      generateComprehensiveHealthCheck
      generateHealthMonitor
      healthCheckResult
      healthCheckStatus;
    
    # Orchestrator functions
    inherit (orchestrator)
      generateDeploymentPlan
      generateDeploymentScripts
      generateMainOrchestratorScript
      generateRollbackScript
      generateStatusScript
      phases
      coreServices;
    
    # Utility functions
    utils = {
      # Generate a complete deployment configuration
      generateDeploymentConfig = manifest: let
        validated = serviceManifest.validateServiceManifest manifest;
        plan = orchestrator.generateDeploymentPlan manifest;
        scripts = orchestrator.generateDeploymentScripts manifest plan;
        mainScript = orchestrator.generateMainOrchestratorScript manifest plan scripts;
        rollbackScript = orchestrator.generateRollbackScript manifest plan;
        statusScript = orchestrator.generateStatusScript manifest plan;
      in
        {
          inherit validated plan scripts mainScript rollbackScript statusScript;
          deploymentOrder = plan.execution_order;
          servicePhases = plan.service_phases;
        };
      
      # Generate a service health check script
      generateServiceHealthCheck = serviceName: 
        healthChecks.generateComprehensiveHealthCheck serviceName;
      
      # Validate a service manifest
      validateManifest = manifest: 
        serviceManifest.validateServiceManifest manifest;
      
      # Get deployment order for services
      getDeploymentOrder = services: 
        serviceManifest.getDeploymentOrder services;
      
      # Check service dependencies
      checkDependencies = serviceName: services: 
        serviceManifest.getServiceDependencies services serviceName;
      
      # Generate Terraform configuration for a service
      generateServiceTerraform = serviceName: service: manifest: let
        workspaceName = terraformRunner.generateWorkspaceName "service" serviceName;
        variablesFile = terraformRunner.generateTerraformVariablesFile manifest service;
        initScript = terraformRunner.generateTerraformInitScript "service" serviceName workspaceName;
        planScript = terraformRunner.generateTerraformPlanScript "service" serviceName workspaceName variablesFile;
        applyScript = terraformRunner.generateTerraformApplyScript "service" serviceName workspaceName;
      in
        {
          inherit workspaceName variablesFile initScript planScript applyScript;
        };
    };
  };
in
  nixmoxLib