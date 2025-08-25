# NixMox library functions
# Main entry point for all library modules

{ lib, config, pkgs, ... }:

let
  # Import all library modules
  serviceManifest = import ./service-manifest.nix { inherit lib config; };
  serviceInterface = import ./service-interface.nix { inherit lib config; };
  terraformRunner = import ./terraform-runner.nix { inherit lib pkgs config; };
  healthChecks = import ./health-checks.nix { inherit lib pkgs; };
  orchestrator = import ./orchestrator.nix { inherit lib config pkgs; };
  
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
      generateServiceTerraform = service: manifest: let
        workspaceName = terraformRunner.generateWorkspaceName "service" service.name;
        variablesFile = terraformRunner.generateTerraformVariablesFile manifest service;
        initScript = terraformRunner.generateTerraformInitScript "service" service.name workspaceName;
        planScript = terraformRunner.generateTerraformPlanScript "service" service.name workspaceName variablesFile;
        applyScript = terraformRunner.generateTerraformApplyScript "service" service.name workspaceName;
      in
        {
          inherit workspaceName variablesFile initScript planScript applyScript;
        };
    };
  };
in
  nixmoxLib