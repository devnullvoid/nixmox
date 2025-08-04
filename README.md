# NixMox - NixOS LXC Orchestration on Proxmox

NixMox is a comprehensive NixOS-based container orchestration system designed for Proxmox VE. It provides a complete self-hosted infrastructure with identity management, monitoring, media services, file sharing, and more.

## 🏗️ Architecture

NixMox consists of multiple LXC containers, each running a specific service:

### Core Infrastructure
- **DNS** (`dns.nixmox.lan`) - Unbound DNS server for internal name resolution
- **Authentik** (`auth.nixmox.lan`) - Identity provider and SSO solution
- **Caddy** (`proxy.nixmox.lan`) - Reverse proxy with forward authentication
- **Monitoring** (`monitoring.nixmox.lan`) - Prometheus + Grafana monitoring stack

### Services
- **Mail** (`mail.nixmox.lan`) - Postfix + Dovecot mail server
- **Media** (`media.nixmox.lan`) - Jellyfin + Arr stack (Sonarr, Radarr, Prowlarr)
- **Nextcloud** (`nextcloud.nixmox.lan`) - File sharing and collaboration platform
- **Vaultwarden** (`vault.nixmox.lan`) - Password manager (Bitwarden-compatible)

## 🚀 Features

### Identity & Access Management
- **Authentik** provides centralized authentication and authorization
- Forward authentication for all services via Caddy
- Single sign-on (SSO) across all applications
- Multi-factor authentication support

### Monitoring & Observability
- **Prometheus** for metrics collection and alerting
- **Grafana** for visualization and dashboards
- **Node Exporter** on all containers for system metrics
- Pre-configured alerting rules for CPU, memory, disk usage

### Media Management
- **Jellyfin** for media streaming and organization
- **Sonarr** for TV show management and automation
- **Radarr** for movie management and automation
- **Prowlarr** for indexer management
- **Transmission** for downloads

### File Sharing & Collaboration
- **Nextcloud** for file storage, sharing, and collaboration
- Calendar and contact synchronization
- Document editing and collaboration
- Mobile and desktop client support

### Security & Privacy
- **Vaultwarden** for secure password management
- End-to-end encryption for sensitive data
- Self-hosted solution with full data control
- Bitwarden-compatible clients

### Infrastructure
- **DNS** for internal service discovery
- **Mail** server for notifications and communication
- **Caddy** with automatic HTTPS and security headers
- Comprehensive firewall rules and security hardening

## 📋 Prerequisites

- Proxmox VE 8.0+
- NixOS 23.11+
- At least 8GB RAM and 100GB storage
- Network access for package downloads and updates

## 🛠️ Installation

### 1. Clone the Repository

```bash
git clone https://github.com/devnullvoid/nixmox.git
cd nixmox
```

### 2. Configure Secrets

Create a `secrets/default.yaml` file with your encrypted secrets:

```yaml
# Example secrets file (encrypted with SOPS)
nixmox:
  password: "your-hashed-password"
  
authentik:
  secret_key: "your-django-secret-key"
  postgres_password: "your-postgres-password"
  redis_password: "your-redis-password"
  admin_password: "your-admin-password"

monitoring:
  grafana_admin_password: "your-grafana-password"

mail:
  admin_password: "your-mail-admin-password"
  postmaster_password: "your-postmaster-password"

nextcloud:
  admin_password: "your-nextcloud-admin-password"
  database_password: "your-nextcloud-db-password"
  redis_password: "your-nextcloud-redis-password"

vaultwarden:
  admin_token: "your-vaultwarden-admin-token"
  jwt_secret: "your-vaultwarden-jwt-secret"
  smtp_password: "your-smtp-password"

media:
  transmission_password: "your-transmission-password"
```

### 3. Build Container Images

```bash
# Build all containers
nix build .#packages.x86_64-linux.nixmox-authentik-lxc
nix build .#packages.x86_64-linux.nixmox-caddy-lxc
nix build .#packages.x86_64-linux.nixmox-monitoring-lxc
nix build .#packages.x86_64-linux.nixmox-dns-lxc
nix build .#packages.x86_64-linux.nixmox-mail-lxc
nix build .#packages.x86_64-linux.nixmox-media-lxc
nix build .#packages.x86_64-linux.nixmox-nextcloud-lxc
nix build .#packages.x86_64-linux.nixmox-vaultwarden-lxc
```

### 4. Deploy to Proxmox

Use the provided deployment scripts:

```bash
# Deploy all containers
./scripts/deploy-remote.sh

# Or deploy individual containers
./scripts/deploy-test.sh authentik
```

## 🔧 Configuration

### Network Setup

The default network configuration uses:
- **Network**: `192.168.50.0/24`
- **Gateway**: `192.168.50.1`
- **DNS**: `192.168.50.9`

### Container IPs

| Service | IP Address | Domain |
|---------|------------|--------|
| Authentik | 192.168.50.2 | auth.nixmox.lan |
| Caddy | 192.168.50.3 | proxy.nixmox.lan |
| Monitoring | 192.168.50.4 | monitoring.nixmox.lan |
| DNS | 192.168.50.9 | dns.nixmox.lan |
| Mail | 192.168.50.5 | mail.nixmox.lan |
| Media | 192.168.50.6 | media.nixmox.lan |
| Nextcloud | 192.168.50.7 | nextcloud.nixmox.lan |
| Vaultwarden | 192.168.50.8 | vault.nixmox.lan |

### Customization

Each module can be customized by modifying the configuration options:

```nix
# Example: Customize Authentik settings
services.nixmox.authentik = {
  enable = true;
  domain = "auth.example.com";
  adminEmail = "admin@example.com";
  # ... other options
};
```

## 🔐 Security

### Default Security Features

- **Firewall Rules**: Comprehensive firewall configuration for each service
- **Systemd Security**: All services run with security hardening
- **HTTPS Everywhere**: Automatic SSL/TLS with Caddy
- **Forward Authentication**: All services protected by Authentik
- **Secrets Management**: SOPS integration for encrypted secrets

### Security Headers

All web services include security headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`

## 📊 Monitoring

### Available Metrics

- **System Metrics**: CPU, memory, disk, network usage
- **Service Health**: HTTP endpoints, database connections
- **Application Metrics**: Custom metrics for each service
- **Log Aggregation**: Centralized logging via systemd-journald

### Grafana Dashboards

Pre-configured dashboards for:
- System overview
- Service health
- Network traffic
- Storage usage
- Application performance

## 🔄 Maintenance

### Updates

```bash
# Update all containers
nix flake update
nix build .#packages.x86_64-linux.nixmox-*-lxc
./scripts/deploy-remote.sh
```

### Backups

Each service includes backup configurations:
- **Database backups**: Automated PostgreSQL/MySQL backups
- **File backups**: Nextcloud and media file backups
- **Configuration backups**: NixOS configuration backups

### Health Checks

All services include health check endpoints:
- HTTP health checks
- Database connectivity checks
- Service-specific health endpoints

## 🐛 Troubleshooting

### Common Issues

1. **Container won't start**: Check logs with `journalctl -u container-name`
2. **Service not accessible**: Verify firewall rules and network configuration
3. **Authentication issues**: Check Authentik configuration and user setup
4. **Database connection errors**: Verify database credentials and connectivity

### Logs

```bash
# View service logs
journalctl -u vaultwarden
journalctl -u nextcloud
journalctl -u jellyfin

# View container logs
pct exec <container-id> journalctl -f
```

### Debug Mode

Enable debug logging by modifying the service configuration:

```nix
services.nixmox.vaultwarden.vaultwarden.environment = {
  LOG_LEVEL = "debug";
  # ... other settings
};
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Development Environment

```bash
# Enter development shell
nix develop

# Build specific container
nix build .#nixosConfigurations.authentik.config.system.build.toplevel

# Test configuration
nixos-generators -f proxmox-lxc -c ./configuration.nix
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [NixOS](https://nixos.org/) for the declarative system configuration
- [Authentik](https://goauthentik.io/) for identity management
- [Jellyfin](https://jellyfin.org/) for media streaming
- [Nextcloud](https://nextcloud.com/) for file sharing
- [Vaultwarden](https://github.com/dani-garcia/vaultwarden) for password management

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/devnullvoid/nixmox/issues)
- **Discussions**: [GitHub Discussions](https://github.com/devnullvoid/nixmox/discussions)
- **Documentation**: [Wiki](https://github.com/devnullvoid/nixmox/wiki)

---

**NixMox** - Self-hosted infrastructure made simple with NixOS and Proxmox. 