# NixMox Library Functions

This directory contains the core library functions for the NixMox deployment orchestration system.

## Overview

The NixMox library provides a comprehensive set of functions for:
- **Service Manifest Management**: Define and validate service configurations
- **Deployment Orchestration**: Automatically handle deployment ordering and dependencies
- **Health Monitoring**: Built-in health checks and monitoring capabilities
- **Resource Management**: Define resource requirements and constraints

## Library Structure

### `service-manifest.nix`
Core service manifest schema and validation functions.

**Key Functions:**
- `serviceManifestSchema`: NixOS option schema for service manifests
- `validateServiceManifest`: Validates service manifest for errors
- `getServiceDependencies`: Resolves service dependency chains
- `getDeploymentOrder`: Generates topological deployment order
- `mkService`: Helper function to create service definitions

### `deployment-orchestrator.nix`
Deployment orchestration logic and script generation.

**Key Functions:**
- `generateDeploymentScript`: Creates deployment scripts for individual services
- `generateRollbackScript`: Creates rollback scripts for services
- `generateDeploymentPlan`: Generates complete deployment plan
- `generateMonitoringScripts`: Creates monitoring and status scripts

### `health-checks.nix`
Health check patterns and monitoring utilities.

**Key Functions:**
- `healthCheckPatterns`: Predefined health check patterns for common services
- `generateHealthCheck`: Creates health check scripts for specific check types
- `generateComprehensiveHealthCheck`: Creates multi-layered health checks
- `generateHealthMonitor`: Creates comprehensive health monitoring scripts

## Usage Examples

### Basic Service Definition

```nix
{ config, lib, ... }:

{
  services.nixmox = {
    enable = true;
    
    network = {
      dns_server = "192.168.1.10";
      gateway = "192.168.1.1";
      network_cidr = "192.168.1.0/24";
      vlan_tag = 100;
    };
    
    services = {
      postgresql = {
        enable = true;
        ip = "192.168.1.11";
        hostname = "db.example.com";
        depends_on = [];
        health_check = "systemctl is-active --quiet postgresql";
      };
      
      app = {
        enable = true;
        ip = "192.168.1.12";
        hostname = "app.example.com";
        depends_on = ["postgresql"];
        health_check = "curl -f -s http://localhost:8080/health";
      };
    };
  };
}
```

### Using Library Functions

```nix
{ config, lib, nixmoxLib, ... }:

let
  # Validate your manifest
  validated = nixmoxLib.utils.validateManifest config.services.nixmox;
  
  # Generate deployment configuration
  deployment = nixmoxLib.utils.generateDeploymentConfig config.services.nixmox;
  
  # Get deployment order
  order = deployment.deploymentOrder;
  
  # Generate health check for a service
  healthCheck = nixmoxLib.utils.generateServiceHealthCheck "postgresql";
in
{
  # Use the generated deployment plan
  systemd.services.deploy-postgresql = {
    script = deployment.phaseScripts.phase1.postgresql;
    wantedBy = ["multi-user.target"];
  };
}
```

## Service Manifest Schema

### Required Fields

- `enable`: Boolean to enable/disable the service
- `ip`: Static IP address for the service
- `hostname`: DNS hostname for the service

### Optional Fields

- `depends_on`: List of service names this service depends on
- `health_check`: Custom health check command or URL
- `restart_policy`: Service restart policy (always, unless-stopped, never)
- `resources`: Resource requirements (memory, cpu, storage)
- `ports`: Network ports the service uses
- `environment`: Environment variables for the service
- `volumes`: Volume mounts for the service

## Health Check Types

### Systemd Service Checks
```nix
health_check = "systemctl is-active --quiet service-name";
```

### HTTP Endpoint Checks
```nix
health_check = "http://localhost:8080/health";
```

### TCP Port Checks
```nix
health_check = "tcp:8080";
```

### Custom Command Checks
```nix
health_check = "pg_isready -h localhost -U username";
```

## Deployment Phases

Services are automatically grouped into deployment phases based on dependencies:

1. **Phase 1**: Infrastructure services (DNS, database, reverse proxy)
2. **Phase 2**: Identity and security services
3. **Phase 3**: Core application services
4. **Phase 4**: Additional services (storage, media)
5. **Phase 5**: Monitoring and observability
6. **Phase 6**: Advanced services (mail, etc.)

## Validation

The library automatically validates:
- **Circular Dependencies**: Prevents circular dependency chains
- **Missing Dependencies**: Ensures all referenced services exist
- **IP Conflicts**: Prevents duplicate IP addresses
- **Hostname Conflicts**: Prevents duplicate hostnames

## Error Handling

All validation errors include detailed error messages:
```
Error: Circular dependency detected: service-a
Error: Missing service dependencies: service-b
Error: Duplicate IP addresses: 192.168.1.10
Error: Duplicate hostnames: app.example.com
```

## Best Practices

1. **Start Simple**: Begin with basic service definitions and add complexity gradually
2. **Use Dependencies**: Always define service dependencies for proper ordering
3. **Health Checks**: Provide meaningful health checks for each service
4. **Resource Limits**: Define resource requirements to prevent resource conflicts
5. **Environment Variables**: Use environment variables for configuration, not hardcoded values
6. **Volume Mounts**: Define persistent storage requirements clearly

## Examples

See the `examples/` directory for complete working configurations:
- `basic.nix`: Simple service setup
- `full-stack.nix`: Complete infrastructure example