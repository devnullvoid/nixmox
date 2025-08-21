# 🧪 NixMox Testing Guide

This guide covers how to test the NixMox project at different levels, from local builds to full deployment.

## 🎯 Testing Strategy Overview

### Phase 1: Local Build Testing ✅ (COMPLETED)
- Individual container builds
- Configuration validation
- Syntax checking

### Phase 2: Configuration Testing 🚧 (IN PROGRESS)
- Service configuration validation
- Cross-container dependency checking
- Build artifact generation

### Phase 3: Container Deployment Testing 📋 (PLANNED)
- Proxmox LXC container creation
- Service startup and health checks
- End-to-end functionality testing

## 🚀 Getting Started with Testing

### Prerequisites
```bash
# Verify Nix is working
nix --version

# Check if you're in the project directory
pwd  # Should show /path/to/nixmox
```

## 🔧 Phase 1: Local Build Testing

### Test Individual Containers
```bash
# Test all containers build successfully
nix build .#nixosConfigurations.caddy.config.system.build.toplevel
nix build .#nixosConfigurations.authentik.config.system.build.toplevel
nix build .#nixosConfigurations.postgresql.config.system.build.toplevel
nix build .#nixosConfigurations.nextcloud.config.system.build.toplevel
nix build .#nixosConfigurations.media.config.system.build.toplevel
nix build .#nixosConfigurations.monitoring.config.system.build.toplevel
nix build .#nixosConfigurations.guacamole.config.system.build.toplevel
nix build .#nixosConfigurations.vaultwarden.config.system.build.toplevel
nix build .#nixosConfigurations.dns.config.system.build.toplevel
nix build .#nixosConfigurations.mail.config.system.build.toplevel
```

### Test Flake Validation
```bash
# Validate entire flake
nix flake check

# Check for evaluation errors
nix eval .#nixosConfigurations
```

## 🎭 Phase 2: Configuration Testing

### What We're Testing
- **Service Configuration**: Verify each service has correct options
- **Dependency Resolution**: Check cross-container dependencies
- **Build Artifacts**: Generate deployable system images
- **Configuration Validation**: Ensure no option conflicts

### Use the Built-in Test Script
```bash
# List available containers
./scripts/deploy-test.sh -l

# Test a specific container
./scripts/deploy-test.sh -t caddy

# Build a container with testing
./scripts/deploy-test.sh -t -o ./builds caddy

# Build all containers for testing
for container in caddy authentik postgresql nextcloud media monitoring guacamole vaultwarden dns mail; do
  echo "Building $container..."
  ./scripts/deploy-test.sh -t -o ./builds $container
done
```

### Test Service Dependencies
```bash
# Test database connections (PostgreSQL first)
./scripts/deploy-test.sh -t postgresql

# Test services that depend on PostgreSQL
./scripts/deploy-test.sh -t nextcloud
./scripts/deploy-test.sh -t authentik
./scripts/deploy-test.sh -t monitoring
```

### Validate Configuration Options
```bash
# Check specific service configurations
nix eval .#nixosConfigurations.caddy.config.services.nixmox.caddy.enable
nix eval .#nixosConfigurations.authentik.config.services.nixmox.authentik.enable
nix eval .#nixosConfigurations.postgresql.config.services.nixmox.postgresql.enable

# Check for configuration conflicts
nix eval .#nixosConfigurations.caddy.config.services.nixmox.caddy.services
```

## 🐳 Phase 3: Container Deployment Testing

### Generate LXC Container Images
```bash
# Generate container images for Proxmox
./scripts/generate-lxc.sh

# Or use nixos-generators directly
nixos-generators -f proxmox-lxc -c ./flake-modules/containers.nix
```

### Test Container Startup (Local)
```bash
# If you have LXC/LXD installed locally
sudo lxc launch ubuntu:22.04 test-container
sudo lxc file push ./builds/caddy/activate test-container/root/
sudo lxc exec test-container -- tar -xf /root/activate
sudo lxc exec test-container -- /nix/var/nix/profiles/system/bin/switch-to-configuration test
```

### Proxmox Integration Testing
```bash
# Use existing deployment scripts
./scripts/deploy-test.sh caddy
./scripts/deploy-test.sh authentik

# For full deployment
./scripts/deploy-remote.sh
```

## 🧪 Testing Scenarios

### 1. Service Startup Testing
```bash
# Test each service starts correctly
for service in caddy authentik postgresql nextcloud media monitoring; do
  echo "Testing $service..."
  ./scripts/deploy-test.sh -t $service
done
```

### 2. Cross-Container Communication Testing
```bash
# Test database connections
./scripts/deploy-test.sh -t postgresql
./scripts/deploy-test.sh -t nextcloud

# Verify Nextcloud can connect to PostgreSQL
# Check logs for connection success
```

### 3. Authentication Flow Testing
```bash
# Test Authentik + Caddy integration
./scripts/deploy-test.sh -t authentik
./scripts/deploy-test.sh -t caddy

# Verify forward auth works
# Test login flow
```

### 4. Monitoring Integration Testing
```bash
# Test monitoring stack
./scripts/deploy-test.sh -t monitoring

# Verify Prometheus scrapes other services
# Check Grafana dashboards load
```

## 🔍 Debugging and Troubleshooting

### Common Issues

#### 1. Build Failures
```bash
# Get detailed error information
nix build .#nixosConfigurations.caddy.config.system.build.toplevel --show-trace

# Check specific configuration
nix eval .#nixosConfigurations.caddy.config.services.nixmox.caddy.enable
```

#### 2. Configuration Issues
```bash
# Validate specific service config
nix eval .#nixosConfigurations.authentik.config.services.nixmox.authentik

# Check for option conflicts
nixos-option services.nixmox.authentik.enable
```

#### 3. Test Script Issues
```bash
# Run with verbose output
bash -x ./scripts/deploy-test.sh -t caddy

# Check script permissions
ls -la ./scripts/deploy-test.sh
chmod +x ./scripts/deploy-test.sh
```

### Log Analysis
```bash
# Check build logs
nix log /nix/store/...-result

# Check service logs (after deployment)
journalctl -u nixmox-authentik
journalctl -u nixmox-caddy
```

## 📊 Testing Checklist

### ✅ Build Testing
- [ ] All containers build successfully
- [ ] Flake validation passes
- [ ] No evaluation warnings (or acceptable ones)

### ✅ Configuration Testing
- [ ] Test script runs without errors
- [ ] All containers pass configuration tests
- [ ] Build artifacts are generated correctly
- [ ] Service dependencies are resolved

### ✅ Integration Testing
- [ ] Cross-container communication works
- [ ] Authentication flow functions
- [ ] Monitoring integration works
- [ ] Database connections succeed

### ✅ Deployment Testing
- [ ] LXC images are generated
- [ ] Containers start successfully
- [ ] Services are accessible
- [ ] Health checks pass

## 🚀 Next Steps

1. **Complete Configuration Testing**: Use the test script to validate all containers
2. **Generate LXC Images**: Create deployable container images
3. **Test Container Startup**: Verify containers start and services run
4. **End-to-End Testing**: Test complete authentication and service flows
5. **Performance Testing**: Measure container startup times and resource usage

## 🆘 Getting Help

- **Build Issues**: Check `nix build` output and use `--show-trace`
- **Test Script Issues**: Use `bash -x` for verbose output
- **Service Issues**: Check logs and verify configuration options
- **Configuration Issues**: Use `nix eval` to debug specific options

## 🎯 Current Status

- **Phase 1**: ✅ Complete - All containers build successfully
- **Phase 2**: 🚧 In Progress - Configuration testing with deploy-test.sh
- **Phase 3**: 📋 Planned - Container deployment and end-to-end testing

---

**Happy Testing!** 🎉
