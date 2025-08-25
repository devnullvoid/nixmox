# NixMox library functions
# Main entry point for all library modules

{ lib, config, pkgs, ... }:

let
  # Import all library modules
  serviceManifest = import ./service-manifest.nix { inherit lib config; };
  deploymentOrchestrator = import ./deployment-orchestrator.nix { inherit lib config pkgs; };
  healthChecks = import ./health-checks.nix { inherit lib pkgs; };
  
  # Combine all library functions
  nixmoxLib = {
    # Service manifest functions
    inherit (serviceManifest)
      serviceManifestSchema
      validateServiceManifest
      getServiceDependencies
      getDeploymentOrder
      mkService;
    
    # Deployment orchestration functions
    inherit (deploymentOrchestrator)
      generateDeploymentScript
      generateRollbackScript
      generateDeploymentPlan
      generateMonitoringScripts
      healthChecks;
    
    # Health check functions
    inherit (healthChecks)
      healthCheckPatterns
      generateHealthCheck
      generateComprehensiveHealthCheck
      generateHealthMonitor
      healthCheckResult
      healthCheckStatus;
    
    # Utility functions
    utils = {
      # Generate a complete deployment configuration
      generateDeploymentConfig = manifest: let
        validated = serviceManifest.validateServiceManifest manifest;
        plan = deploymentOrchestrator.generateDeploymentPlan manifest;
        healthMonitor = healthChecks.generateHealthMonitor manifest.services;
      in
        {
          inherit validated plan healthMonitor;
          deploymentOrder = plan.deploymentOrder;
          phaseScripts = plan.phaseScripts;
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
    };
  };
in
  nixmoxLib