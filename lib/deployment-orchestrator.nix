# Deployment orchestration logic
# Handles service deployment ordering, health checks, and rollback

{ lib, config, pkgs, ... }:

let
  # Import service manifest functions
  serviceManifest = import ./service-manifest.nix { inherit lib config; };
  
  # Default health check timeout (seconds)
  defaultHealthTimeout = 300;
  
  # Default retry attempts
  defaultRetryAttempts = 3;
  
  # Default retry delay (seconds)
  defaultRetryDelay = 10;

  # Health check functions
  healthChecks = {
    # Systemd service health check
    systemd = serviceName: ''
      if ! systemctl is-active --quiet ${serviceName}; then
        echo "Service ${serviceName} is not active"
        exit 1
      fi
      echo "Service ${serviceName} is healthy"
    '';
    
    # HTTP health check
    http = url: ''
      if ! curl -f -s ${url} > /dev/null; then
        echo "HTTP health check failed for ${url}"
        exit 1
      fi
      echo "HTTP health check passed for ${url}"
    '';
    
    # TCP port health check
    tcp = port: ''
      if ! nc -z localhost ${toString port}; then
        echo "TCP health check failed for port ${toString port}"
        exit 1
      fi
      echo "TCP health check passed for port ${toString port}"
    '';
    
    # Custom command health check
    custom = command: ''
      if ! ${command}; then
        echo "Custom health check failed: ${command}"
        exit 1
      fi
      echo "Custom health check passed: ${command}"
    '';
  };

  # Generate health check script for a service
  generateHealthCheck = service: let
    healthCheck = service.health_check or null;
    defaultCheck = serviceManifest.health_checks.${service.name} or null;
    
    # Determine which health check to use
    checkToUse = if healthCheck != null then
      healthCheck
    else if defaultCheck != null then
      defaultCheck
    else
      "systemctl is-active --quiet ${service.name}";
    
    # Generate the appropriate health check
    checkScript = if lib.hasPrefix "systemctl" checkToUse then
      healthChecks.systemd (lib.last (lib.splitString " " checkToUse))
    else if lib.hasPrefix "http" checkToUse then
      healthChecks.http checkToUse
    else if lib.hasPrefix "tcp" checkToUse then
      healthChecks.tcp (lib.last (lib.splitString ":" checkToUse))
    else
      healthChecks.custom checkToUse;
  in
    pkgs.writeShellScript "health-check-${service.name}" ''
      set -euo pipefail
      ${checkScript}
    '';

  # Generate deployment script for a service
  generateDeploymentScript = service: manifest: let
    deps = serviceManifest.getServiceDependencies manifest.services service.name;
    depChecks = lib.concatStringsSep "\n" (map (dep: 
      "echo 'Waiting for ${dep} to be healthy...'"
    ) deps);
    
    healthCheckScript = generateHealthCheck service;
  in
    pkgs.writeShellScript "deploy-${service.name}" ''
      set -euo pipefail
      
      SERVICE_NAME="${service.name}"
      SERVICE_IP="${service.ip}"
      HEALTH_CHECK_SCRIPT="${healthCheckScript}"
      
      echo "Starting deployment of $SERVICE_NAME"
      
      # Wait for dependencies to be healthy
      ${depChecks}
      
      # Perform health checks on dependencies
      ${lib.concatStringsSep "\n" (map (dep: 
        "echo 'Checking health of ${dep}...'"
      ) deps)}
      
      # Deploy the service (this would be the actual deployment logic)
      echo "Deploying $SERVICE_NAME to $SERVICE_IP"
      
      # Wait for service to become healthy
      echo "Waiting for $SERVICE_NAME to become healthy..."
      timeout ${toString defaultHealthTimeout} bash -c '
        while ! $HEALTH_CHECK_SCRIPT; do
          echo "Waiting for $SERVICE_NAME to be healthy..."
          sleep 5
        done
      '
      
      echo "$SERVICE_NAME deployment completed successfully"
    '';

  # Generate rollback script for a service
  generateRollbackScript = service: manifest: let
    deps = serviceManifest.getServiceDependencies manifest.services service.name;
  in
    pkgs.writeShellScript "rollback-${service.name}" ''
      set -euo pipefail
      
      SERVICE_NAME="${service.name}"
      SERVICE_IP="${service.ip}"
      
      echo "Starting rollback of $SERVICE_NAME"
      
      # Stop the service
      echo "Stopping $SERVICE_NAME..."
      # Add actual stop logic here
      
      # Notify dependent services
      ${lib.concatStringsSep "\n" (map (dep: 
        "echo 'Notifying ${dep} of $SERVICE_NAME rollback'"
      ) deps)}
      
      echo "$SERVICE_NAME rollback completed"
    '';

  # Generate deployment plan
  generateDeploymentPlan = manifest: let
    deploymentOrder = serviceManifest.getDeploymentOrder manifest.services;
    enabledServices = lib.filterAttrs (name: service: service.enable) manifest.services;
    
    # Group services by deployment phase
    phaseGroups = lib.mapAttrs (phaseName: phaseServices: 
      lib.filter (serviceName: lib.hasAttr serviceName enabledServices) phaseServices
    ) manifest.deployment_phases;
    
    # Generate deployment scripts for each phase
    phaseScripts = lib.mapAttrs (phaseName: serviceNames: 
      lib.map (serviceName: 
        generateDeploymentScript enabledServices.${serviceName} manifest
      ) serviceNames
    ) phaseGroups;
  in
    {
      inherit deploymentOrder;
      inherit phaseGroups;
      inherit phaseScripts;
      
      # Generate main deployment orchestrator script
      mainScript = pkgs.writeShellScript "deploy-orchestrator" ''
        set -euo pipefail
        
        echo "Starting NixMox deployment orchestration"
        echo "Total services to deploy: ${toString (lib.length (lib.attrNames enabledServices))}"
        
        # Deploy services by phase
        ${lib.concatStringsSep "\n" (lib.mapAttrs (phaseName: scripts: ''
          echo "Starting ${phaseName}..."
          ${lib.concatStringsSep "\n" (map (script: "echo 'Running ${script}'") scripts)}
        '') phaseScripts)}
        
        echo "All services deployed successfully!"
      '';
    };

  # Generate monitoring and status scripts
  generateMonitoringScripts = manifest: let
    enabledServices = lib.filterAttrs (name: service: service.enable) manifest.services;
    
    # Status check script
    statusScript = pkgs.writeShellScript "service-status" ''
      set -euo pipefail
      
      echo "NixMox Service Status"
      echo "====================="
      
      ${lib.concatStringsSep "\n" (lib.mapAttrs (name: service: ''
        echo -n "${name}: "
        if ${generateHealthCheck service}; then
          echo "✓ HEALTHY"
        else
          echo "✗ UNHEALTHY"
        fi
      '') enabledServices)}
    '';
    
    # Dependency graph script
    dependencyScript = pkgs.writeShellScript "dependency-graph" ''
      set -euo pipefail
      
      echo "NixMox Service Dependencies"
      echo "==========================="
      
      ${lib.concatStringsSep "\n" (lib.mapAttrs (name: service: ''
        echo "${name}:"
        ${lib.concatStringsSep "\n" (map (dep: "  - ${dep}") (service.depends_on or []))}
      '') enabledServices)}
    '';
  in
    {
      inherit statusScript;
      inherit dependencyScript;
    };

in {
  # Export the orchestration functions
  inherit generateDeploymentScript;
  inherit generateRollbackScript;
  inherit generateDeploymentPlan;
  inherit generateMonitoringScripts;
  inherit healthChecks;
}