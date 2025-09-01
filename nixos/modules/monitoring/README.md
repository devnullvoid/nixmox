# NixMox Monitoring Module

A comprehensive monitoring stack for NixMox infrastructure, providing metrics collection, visualization, alerting, and log aggregation.

## Architecture

### Distributed Monitoring Design

The monitoring architecture follows a distributed approach:

- **Central Monitoring Host**: Runs Prometheus, Grafana, Alertmanager, Loki, and Promtail
- **Service Hosts**: Run exporters (Node Exporter, PostgreSQL Exporter, Caddy Exporter) via the common module
- **Manifest-Driven**: All configurations are derived from `service-manifest.nix` for consistency

### Component Overview

| Component | Purpose | Port | Location |
|-----------|---------|------|----------|
| **Prometheus** | Metrics collection and time-series database | 9090 | Monitoring host |
| **Grafana** | Visualization and dashboards | 3000 | Monitoring host |
| **Alertmanager** | Alert routing and notification | 9093 | Monitoring host |
| **Loki** | Log aggregation | 3100 | Monitoring host |
| **Promtail** | Log collection agent | 9080 | Monitoring host |
| **Node Exporter** | System metrics | 9100 | All hosts (via common module) |
| **PostgreSQL Exporter** | Database metrics | 9187 | PostgreSQL host |
| **Caddy Exporter** | Reverse proxy metrics | 2019 | Caddy host |

### Data Flow

```
Service Hosts (Exporters) → Prometheus (Metrics)
Service Hosts (Promtail) → Loki (Logs)
Prometheus → Alertmanager (Alerts)
Prometheus + Loki → Grafana (Visualization)
```

## Configuration

### Basic Usage

```nix
{
  services.nixmox.monitoring = {
    enable = true;
    subdomain = "monitoring";
    hostName = "monitoring.nixmox.lan";
  };
}
```

### Incremental Deployment

For testing and debugging, deploy components incrementally:

```nix
{
  services.nixmox.monitoring = {
    enable = true;
    
    # Start with just Prometheus
    prometheus = {
      enable = true;
    };

    # Add components one by one as you verify each works
    # grafana = { enable = true; };
    # alertmanager = { enable = true; };
    # loki = { enable = true; };
    # promtail = { enable = true; };
  };
}
```

## Deployment Process

### Step 1: Deploy with Prometheus Only

The monitoring module starts with only Prometheus enabled by default. Deploy:

```bash
./scripts/deploy-orchestrator.sh --service monitoring
```

**Test Prometheus:**
```bash
# SSH to monitoring host
ssh root@192.168.99.18

# Check service status
systemctl status prometheus

# Test metrics endpoint
curl http://localhost:9090/metrics

# Check targets
curl http://localhost:9090/api/v1/targets

# Check logs
journalctl -u prometheus -f
```

### Step 2: Enable Grafana

When Prometheus is working, uncomment in `nixmox/nixos/modules/monitoring/default.nix`:
```nix
services.nixmox.monitoring.grafana.enable = true;
```

Redeploy:
```bash
./scripts/deploy-orchestrator.sh --service monitoring
```

**Test Grafana:**
```bash
# Check service status
systemctl status grafana

# Test health endpoint
curl http://localhost:3000/api/health

# Check logs
journalctl -u grafana -f

# Access web interface (via Caddy proxy)
# https://monitoring.nixmox.lan
```

### Step 3: Enable Alertmanager

When basic monitoring is working, uncomment:
```nix
services.nixmox.monitoring.alertmanager.enable = true;
```

**Test Alertmanager:**
```bash
# Check service status
systemctl status alertmanager

# Test status endpoint
curl http://localhost:9093/api/v1/status

# Check logs
journalctl -u alertmanager -f
```

### Step 4: Enable Loki

When monitoring is stable, uncomment:
```nix
services.nixmox.monitoring.loki.enable = true;
```

**Test Loki:**
```bash
# Check service status
systemctl status loki

# Test ready endpoint
curl http://localhost:3100/ready

# Check logs
journalctl -u loki -f
```

### Step 5: Enable Promtail

When Loki is working, uncomment:
```nix
services.nixmox.monitoring.promtail.enable = true;
```

**Test Promtail:**
```bash
# Check service status
systemctl status promtail

# Test metrics endpoint
curl http://localhost:9080/metrics

# Check logs
journalctl -u promtail -f
```

## Advanced Configuration

### Prometheus Configuration

```nix
{
  services.nixmox.monitoring.prometheus = {
    enable = true;
    retention = "30d";
    scrapeInterval = "15s";
    evaluationInterval = "15s";
  };
}
```

### Grafana Configuration

```nix
{
  services.nixmox.monitoring.grafana = {
    enable = true;
    adminPassword = "changeme"; # Override via SOPS
    dbPassword = "changeme";    # Override via SOPS
  };
}
```

### Alertmanager Configuration

```nix
{
  services.nixmox.monitoring.alertmanager = {
    enable = true;
    port = 9093;
  };
}
```

### Loki Configuration

```nix
{
  services.nixmox.monitoring.loki = {
    enable = true;
    port = 3100;
    retention = "168h"; # 7 days
  };
}
```

### Promtail Configuration

```nix
{
  services.nixmox.monitoring.promtail = {
    enable = true;
    port = 9080;
    lokiUrl = "http://127.0.0.1:3100/loki/api/v1/push";
  };
}
```

## Monitoring Rules

### Basic Alerting Rules

Add these to your monitoring host configuration when Alertmanager is enabled:

```nix
{
  services.prometheus.rules = {
    # High CPU usage alert
    high_cpu_usage = {
      alert = "HighCPUUsage";
      expr = "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 80";
      for = "5m";
      labels = {
        severity = "warning";
      };
      annotations = {
        summary = "High CPU usage on {{ $labels.instance }}";
        description = "CPU usage is above 80% for more than 5 minutes on {{ $labels.instance }}";
      };
    };

    # High memory usage alert
    high_memory_usage = {
      alert = "HighMemoryUsage";
      expr = "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85";
      for = "5m";
      labels = {
        severity = "warning";
      };
      annotations = {
        summary = "High memory usage on {{ $labels.instance }}";
        description = "Memory usage is above 85% for more than 5 minutes on {{ $labels.instance }}";
      };
    };

    # Low disk space alert
    low_disk_space = {
      alert = "LowDiskSpace";
      expr = "(node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100 < 10";
      for = "5m";
      labels = {
        severity = "critical";
      };
      annotations = {
        summary = "Low disk space on {{ $labels.instance }}";
        description = "Disk space is below 10% on {{ $labels.instance }}";
      };
    };

    # Service down alert
    service_down = {
      alert = "ServiceDown";
      expr = "up == 0";
      for = "1m";
      labels = {
        severity = "critical";
      };
      annotations = {
        summary = "Service {{ $labels.job }} is down on {{ $labels.instance }}";
        description = "Service {{ $labels.job }} has been down for more than 1 minute on {{ $labels.instance }}";
      };
    };
  };
}
```

## Troubleshooting

### Common Issues

#### Prometheus Targets Down
- Check if Node Exporter is running on target hosts: `systemctl status prometheus-node-exporter`
- Verify firewall rules allow port 9100
- Check network connectivity between monitoring and target hosts

#### Grafana Can't Connect to Prometheus
- Verify Prometheus is running: `systemctl status prometheus`
- Check Grafana datasource configuration points to `http://127.0.0.1:9090`
- Review Grafana logs: `journalctl -u grafana -f`

#### Loki Not Receiving Logs
- Verify Promtail is running: `systemctl status promtail`
- Check Promtail configuration points to correct Loki URL
- Review Promtail logs: `journalctl -u promtail -f`

#### Alertmanager Not Sending Notifications
- Check Alertmanager configuration for correct SMTP settings
- Verify network connectivity to mail server
- Review Alertmanager logs: `journalctl -u alertmanager -f`

### Debugging Commands

#### Service Status
```bash
# Check all monitoring services
systemctl status prometheus grafana alertmanager loki promtail

# Check specific service
systemctl status prometheus
```

#### Service Logs
```bash
# Follow logs for specific service
journalctl -u prometheus -f
journalctl -u grafana -f
journalctl -u alertmanager -f
journalctl -u loki -f
journalctl -u promtail -f

# View recent logs
journalctl -u prometheus -n 50
```

#### Health Checks
```bash
# Prometheus
curl http://localhost:9090/metrics
curl http://localhost:9090/api/v1/targets

# Grafana
curl http://localhost:3000/api/health

# Alertmanager
curl http://localhost:9093/api/v1/status

# Loki
curl http://localhost:3100/ready

# Promtail
curl http://localhost:9080/metrics
```

#### Network Connectivity
```bash
# Test connectivity to target hosts
telnet postgresql.nixmox.lan 9187
telnet caddy.nixmox.lan 2019

# Check DNS resolution
nslookup postgresql.nixmox.lan
nslookup caddy.nixmox.lan
```

### Rollback Strategy

If a component fails after enabling:

1. **Comment out the problematic component** in `nixmox/nixos/modules/monitoring/default.nix`
2. **Redeploy**: `./scripts/deploy-orchestrator.sh --service monitoring`
3. **Debug the issue** using the troubleshooting commands above
4. **Re-enable** when the issue is resolved

## Integration with NixMox Architecture

### Manifest-Driven Configuration

All monitoring configurations are derived from `service-manifest.nix`:

- **Service discovery**: Prometheus targets are automatically generated from manifest
- **Hostname resolution**: Uses manifest-defined hostnames and IPs
- **Database connections**: Grafana connects to PostgreSQL using manifest configuration
- **Authentication**: Integrates with Authentik OIDC provider

### SOPS Integration

Sensitive configuration values should be managed via SOPS:

```yaml
# secrets/default.yaml
monitoring:
  grafana_admin_password: "your-secure-password"
  grafana_db_password: "your-db-password"
```

### Caddy Integration

Monitoring services are exposed via Caddy reverse proxy:

- **Domain**: `monitoring.nixmox.lan`
- **Authentication**: OIDC via Authentik
- **TLS**: Automatic certificate management
- **Upstream**: `192.168.99.18:9090` (Prometheus)

## File Structure

```
nixmox/nixos/modules/monitoring/
├── default.nix              # Main module with imports and default config
├── prometheus.nix           # Prometheus configuration
├── grafana.nix              # Grafana configuration  
├── alertmanager.nix         # Alertmanager configuration
├── loki.nix                 # Loki configuration
├── promtail.nix             # Promtail configuration
└── README.md                # This documentation
```

## Dependencies

### Required Services
- **PostgreSQL**: Database for Grafana
- **Caddy**: Reverse proxy and authentication
- **Authentik**: OIDC authentication provider

### Optional Services
- **Mail server**: For Alertmanager notifications
- **Other services**: For additional metrics via exporters

## Security Considerations

- All services listen on loopback only (127.0.0.1)
- Access is controlled via Caddy reverse proxy with OIDC authentication
- Sensitive passwords should be managed via SOPS
- Firewall rules restrict access to monitoring ports
- TLS encryption is handled by Caddy
