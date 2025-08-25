# Health check definitions and utilities
# Provides standardized health check patterns for common services

{ lib, pkgs, ... }:

let
  # Common health check patterns
  healthCheckPatterns = {
    # Systemd service checks
    systemd = {
      postgresql = "systemctl is-active --quiet postgresql";
      caddy = "systemctl is-active --quiet caddy";
      authentik = "systemctl is-active --quiet authentik";
      guacamole = "systemctl is-active --quiet tomcat && systemctl is-active --quiet guacamole-server";
      vaultwarden = "systemctl is-active --quiet vaultwarden";
      nextcloud = "systemctl is-active --quiet nextcloud-fpm && systemctl is-active --quiet nginx";
      monitoring = "systemctl is-active --quiet prometheus && systemctl is-active --quiet grafana";
      mail = "systemctl is-active --quiet postfix && systemctl is-active --quiet dovecot";
    };
    
    # HTTP endpoint checks
    http = {
      caddy = "curl -f -s http://localhost:2019/health";
      authentik = "curl -f -s http://localhost:9000/health";
      guacamole = "curl -f -s http://localhost:8280/guacamole/";
      vaultwarden = "curl -f -s http://localhost:8080/health";
      nextcloud = "curl -f -s http://localhost:8080/status.php";
      monitoring = "curl -f -s http://localhost:9090/-/healthy";
      grafana = "curl -f -s http://localhost:3000/api/health";
    };
    
    # TCP port checks
    tcp = {
      postgresql = "nc -z localhost 5432";
      caddy = "nc -z localhost 2019";
      authentik = "nc -z localhost 9000";
      guacamole = "nc -z localhost 8280";
      vaultwarden = "nc -z localhost 8080";
      nextcloud = "nc -z localhost 8080";
      monitoring = "nc -z localhost 9090";
      grafana = "nc -z localhost 3000";
    };
    
    # Database connection checks
    database = {
      postgresql = "sudo -u postgres psql -c 'SELECT 1;' > /dev/null 2>&1";
      mysql = "mysql -u root -e 'SELECT 1;' > /dev/null 2>&1";
    };
    
    # File system checks
    filesystem = {
      storage = "df -h /var/lib | grep -v 'Use%' | awk '{if (\$5 > 90) exit 1}'; echo 'Storage OK'";
      logs = "test -f /var/log/syslog && echo 'Logs accessible'";
    };
    
    # Network connectivity checks
    network = {
      dns = "nslookup google.com > /dev/null 2>&1";
      gateway = "ping -c 1 $(ip route | grep default | awk '{print \$3}') > /dev/null 2>&1";
      internet = "curl -f -s --connect-timeout 5 https://httpbin.org/get > /dev/null 2>&1";
    };
  };

  # Generate health check script for a service
  generateHealthCheck = serviceName: checkType: let
    check = healthCheckPatterns.${checkType}.${serviceName} or null;
    
    if check == null then
      throw "No ${checkType} health check found for service ${serviceName}"
    else
      pkgs.writeShellScript "health-check-${serviceName}-${checkType}" ''
        set -euo pipefail
        
        # Health check for ${serviceName} (${checkType})
        if ${check}; then
          echo "✓ ${serviceName} (${checkType}) health check passed"
          exit 0
        else
          echo "✗ ${serviceName} (${checkType}) health check failed"
          exit 1
        fi
      '';
  };

  # Generate comprehensive health check for a service
  generateComprehensiveHealthCheck = serviceName: let
    checks = lib.filter (checkType: 
      lib.hasAttr serviceName healthCheckPatterns.${checkType}
    ) (lib.attrNames healthCheckPatterns);
    
    checkScripts = lib.map (checkType: 
      generateHealthCheck serviceName checkType
    ) checks;
    
    # Combine all health checks
    combinedScript = pkgs.writeShellScript "health-check-${serviceName}-comprehensive" ''
      set -euo pipefail
      
      SERVICE_NAME="${serviceName}"
      echo "Running comprehensive health checks for $SERVICE_NAME"
      
      # Run all available health checks
      ${lib.concatStringsSep "\n" (lib.map (script: ''
        echo "Running ${script}..."
        if ${script}; then
          echo "✓ Health check passed"
        else
          echo "✗ Health check failed"
          exit 1
        fi
      '') checkScripts)}
      
      echo "✓ All health checks passed for $SERVICE_NAME"
    '';
  in
    combinedScript;

  # Health check result types
  healthCheckResult = {
    healthy = "healthy";
    unhealthy = "unhealthy";
    unknown = "unknown";
    degraded = "degraded";
  };

  # Health check status with metadata
  healthCheckStatus = {
    status = healthCheckResult.unknown;
    timestamp = null;
    duration = null;
    details = {};
    lastCheck = null;
  };

  # Generate health check monitoring script
  generateHealthMonitor = services: let
    enabledServices = lib.filterAttrs (name: service: service.enable) services;
    
    # Generate health check for each service
    serviceChecks = lib.mapAttrs (name: service: 
      generateComprehensiveHealthCheck name
    ) enabledServices;
    
    # Main monitoring script
    mainScript = pkgs.writeShellScript "health-monitor" ''
      set -euo pipefail
      
      echo "NixMox Health Monitor"
      echo "====================="
      echo "Timestamp: $(date -Iseconds)"
      echo ""
      
      OVERALL_STATUS=0
      
      ${lib.concatStringsSep "\n" (lib.mapAttrs (name: script: ''
        echo "Checking ${name}..."
        if ${script}; then
          echo "✓ ${name}: HEALTHY"
        else
          echo "✗ ${name}: UNHEALTHY"
          OVERALL_STATUS=1
        fi
        echo ""
      '') serviceChecks)}
      
      if [ $OVERALL_STATUS -eq 0 ]; then
        echo "Overall Status: ✓ ALL SERVICES HEALTHY"
        exit 0
      else
        echo "Overall Status: ✗ SOME SERVICES UNHEALTHY"
        exit 1
      fi
    '';
  in
    mainScript;

in {
  # Export health check functions and patterns
  inherit healthCheckPatterns;
  inherit generateHealthCheck;
  inherit generateComprehensiveHealthCheck;
  inherit generateHealthMonitor;
  inherit healthCheckResult;
  inherit healthCheckStatus;
}