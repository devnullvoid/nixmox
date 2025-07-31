# NixMox Deployment Guide

This guide explains how to deploy and test NixMox containers on Proxmox VE.

## 🚀 Quick Start

### 1. Build a Container

```bash
# Build the authentik container
./scripts/deploy-test.sh authentik

# Build the caddy container
./scripts/deploy-test.sh caddy

# Build the monitoring container
./scripts/deploy-test.sh monitoring
```

### 2. Generate LXC Images (Optional)

```bash
# Generate Proxmox LXC image for authentik
./scripts/generate-lxc.sh authentik

# List available containers
./scripts/generate-lxc.sh -l
```

## 🔧 Manual LXC Deployment

### Step 1: Create LXC Container on Proxmox

1. **Create a new LXC container** in Proxmox VE
2. **Use a minimal template** (Ubuntu 22.04 or similar)
3. **Configure resources**:
   - CPU: 2 cores
   - RAM: 2GB
   - Storage: 10GB
   - Network: Bridge with static IP

### Step 2: Upload and Extract NixOS System

```bash
# On your development machine
cd builds/authentik
tar -czf authentik-system.tar.gz *

# Upload to Proxmox host
scp authentik-system.tar.gz root@proxmox-host:/tmp/

# On Proxmox host
cd /var/lib/lxc/YOUR_CONTAINER_ID/rootfs
tar -xzf /tmp/authentik-system.tar.gz
```

### Step 3: Configure Container for NixOS

```bash
# On Proxmox host, inside container rootfs
mkdir -p /etc/nixos
cp /nix/store/*/etc/nixos/configuration.nix /etc/nixos/

# Set up Nix
curl -L https://nixos.org/nix/install | sh
source /root/.nix-profile/etc/profile.d/nix.sh

# Activate the NixOS configuration
/nix/store/*/activate
```

## 🧪 Testing with SSH

### Default Credentials

All containers use these default credentials for initial testing:

- **Username**: `nixmox`
- **Password**: `nixmox`
- **SSH Port**: `22`

### SSH Connection

```bash
# Connect to the container
ssh nixmox@CONTAINER_IP

# Test basic functionality
systemctl status sshd
systemctl status postgresql  # For authentik container
systemctl status redis       # For authentik container
```

### Security Notes

⚠️ **Important**: These are development/testing credentials. For production:

1. **Change the password immediately** after first login
2. **Set up SSH keys** for key-based authentication
3. **Disable password authentication** in production
4. **Use SOPS** for secret management

## 📋 Container-Specific Testing

### Authentik Container

```bash
# Test PostgreSQL
sudo -u postgres psql -c "SELECT version();"

# Test Redis
redis-cli ping

# Test Authentik (when implemented)
curl http://localhost:9000/health/
```

### Caddy Container

```bash
# Test Caddy
curl http://localhost:2019/config/
systemctl status caddy
```

### Monitoring Container

```bash
# Test Prometheus
curl http://localhost:9090/api/v1/status/config

# Test Grafana
curl http://localhost:3000/api/health
```

## 🔍 Troubleshooting

### Common Issues

1. **SSH Connection Refused**
   - Check if container is running
   - Verify SSH service is enabled
   - Check firewall rules

2. **Services Not Starting**
   - Check systemd logs: `journalctl -xe`
   - Verify dependencies are installed
   - Check configuration syntax

3. **Network Issues**
   - Verify container has network access
   - Check DNS resolution
   - Test connectivity: `ping 8.8.8.8`

### Debug Commands

```bash
# Check system status
systemctl status

# View recent logs
journalctl -f

# Check network
ip addr show
ping google.com

# Check disk space
df -h

# Check memory usage
free -h
```

## 🚀 Production Deployment

### 1. Security Hardening

```bash
# Change default password
passwd nixmox

# Set up SSH keys
ssh-keygen -t ed25519 -C "nixmox@production"
# Add public key to ~/.ssh/authorized_keys

# Disable password authentication
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### 2. Backup Configuration

```bash
# Backup current configuration
sudo cp /etc/nixos/configuration.nix /etc/nixos/configuration.nix.backup

# Create deployment script
cat > deploy.sh << 'EOF'
#!/bin/bash
nixos-rebuild switch
EOF
chmod +x deploy.sh
```

### 3. Monitoring Setup

```bash
# Enable monitoring
sudo systemctl enable prometheus-node-exporter
sudo systemctl start prometheus-node-exporter

# Check metrics
curl http://localhost:9100/metrics
```

## 📊 Performance Tuning

### Resource Optimization

```bash
# Monitor resource usage
htop
iotop
nethogs

# Optimize PostgreSQL (for authentik)
sudo -u postgres psql -c "ALTER SYSTEM SET shared_buffers = '256MB';"
sudo -u postgres psql -c "ALTER SYSTEM SET effective_cache_size = '1GB';"
sudo systemctl restart postgresql
```

### Network Optimization

```bash
# Optimize network settings
echo 'net.core.rmem_max = 16777216' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## 🔄 Updates and Maintenance

### System Updates

```bash
# Update NixOS
sudo nixos-rebuild switch --upgrade

# Update specific packages
sudo nix-env -u '*'

# Garbage collection
sudo nix-collect-garbage -d
```

### Service Updates

```bash
# Restart services
sudo systemctl restart postgresql
sudo systemctl restart redis
sudo systemctl restart caddy

# Check service status
sudo systemctl status postgresql redis caddy
```

---

**Next Steps**: After successful testing, proceed to Phase 2 of the TODO to implement additional service modules. 