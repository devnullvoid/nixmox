# NixMox Project TODO

## 🎯 Project Overview
NixMox is a multi-container NixOS deployment system for Proxmox VE with unified management and single sign-on.

## 📋 Current Status

### ✅ **Phase 1: Core Infrastructure (COMPLETED)**
- [x] **Core Flake Structure**
  - [x] Multi-container NixOS flake setup
  - [x] Inputs for nixpkgs, sops-nix, authentik-nix, nixos-generators
  - [x] Development shell with necessary tools
  - [x] Container image generation capabilities
  - [x] Support for x86_64-linux and aarch64-linux

- [x] **Common Module** (`modules/common/default.nix`)
  - [x] Shared configuration for all containers
  - [x] SSH hardening with proper security settings
  - [x] Node exporter for monitoring
  - [x] Basic system utilities and packages
  - [x] Proper user management
  - [x] Fixed all NixOS module conflicts using `lib.mkForce`

- [x] **Authentik Module** (`modules/authentik/default.nix`)
  - [x] Identity provider configuration (placeholder)
  - [x] PostgreSQL database setup
  - [x] Redis configuration (fixed Redis option names)
  - [x] Proper option definitions with defaults
  - [x] Ready for authentik-nix integration

- [x] **Caddy Module** (`modules/caddy/default.nix`)
  - [x] Reverse proxy with forward authentication
  - [x] TLS termination and automatic HTTPS
  - [x] Service routing configuration
  - [x] Security headers and best practices

- [x] **Monitoring Module** (`modules/monitoring/default.nix`)
  - [x] Prometheus configuration with alerting
  - [x] Grafana setup with dashboards
  - [x] PostgreSQL exporter
  - [x] Health checks and systemd services

- [x] **Secrets Management**
  - [x] SOPS integration for encrypted secrets
  - [x] Template for all service secrets (`secrets/default.yaml`)
  - [x] Age key support for decryption

### 🔄 **Phase 2: Service Modules (IN PROGRESS)**

#### 🚀 **High Priority**
- [ ] **Mail Module** (`modules/mail/default.nix`)
  - [ ] Simple NixOS Mailserver integration
  - [ ] Postfix configuration
  - [ ] Dovecot configuration
  - [ ] SpamAssassin setup
  - [ ] DKIM/DMARC configuration
  - [ ] Webmail interface (Roundcube)

- [ ] **Media Module** (`modules/media/default.nix`)
  - [ ] Jellyfin media server
  - [ ] Sonarr for TV shows
  - [ ] Radarr for movies
  - [ ] Lidarr for music
  - [ ] Prowlarr for indexers
  - [ ] Transmission for downloads

- [ ] **Nextcloud Module** (`modules/nextcloud/default.nix`)
  - [ ] Nextcloud installation
  - [ ] PostgreSQL backend
  - [ ] Redis for caching
  - [ ] File storage configuration
  - [ ] App store integration

- [ ] **Vaultwarden Module** (`modules/vaultwarden/default.nix`)
  - [ ] Vaultwarden (Bitwarden-compatible) server
  - [ ] SQLite database
  - [ ] Backup configuration
  - [ ] Admin interface

- [ ] **DNS Module** (`modules/dns/default.nix`)
  - [ ] Unbound DNS resolver
  - [ ] DNS over HTTPS (DoH)
  - [ ] Ad blocking lists
  - [ ] Local domain resolution

#### 🔧 **Medium Priority**
- [ ] **Backup Module** (`modules/backup/default.nix`)
  - [ ] Restic backup automation
  - [ ] S3/Backblaze B2 integration
  - [ ] Backup scheduling
  - [ ] Restore procedures

- [ ] **Monitoring Enhancements**
  - [ ] Custom Grafana dashboards
  - [ ] Alert notifications (email, Slack)
  - [ ] Log aggregation (Loki)
  - [ ] Service discovery

### 🎨 **Phase 3: Management Plane (PLANNED)**

#### 🚀 **High Priority**
- [ ] **Go Backend** (`backend/`)
  - [ ] Proxmox API integration
  - [ ] Container management
  - [ ] Service deployment
  - [ ] Configuration management
  - [ ] REST API endpoints

- [ ] **React Frontend** (`frontend/`)
  - [ ] Service dashboard
  - [ ] Container management UI
  - [ ] Configuration editor
  - [ ] Monitoring views
  - [ ] User management

#### 🔧 **Medium Priority**
- [ ] **CLI Tool** (`cli/`)
  - [ ] Command-line interface
  - [ ] Deployment commands
  - [ ] Configuration validation
  - [ ] Health checks

### 🚀 **Phase 4: Advanced Features (PLANNED)**

#### 🎯 **High Priority**
- [ ] **Multi-Environment Support**
  - [ ] Development environment
  - [ ] Staging environment
  - [ ] Production environment
  - [ ] Environment-specific configurations

- [ ] **Service Discovery**
  - [ ] Automatic service detection
  - [ ] Dynamic configuration updates
  - [ ] Health monitoring
  - [ ] Load balancing

#### 🔧 **Medium Priority**
- [ ] **Advanced Monitoring**
  - [ ] Custom metrics collection
  - [ ] Performance profiling
  - [ ] Capacity planning
  - [ ] Cost optimization

- [ ] **Security Enhancements**
  - [ ] Network segmentation
  - [ ] Intrusion detection
  - [ ] Vulnerability scanning
  - [ ] Compliance reporting

### 🐛 **Current Issues to Fix**

#### 🔥 **Critical**
- [ ] **Authentik Integration**
  - [ ] Fix authentik-nix module import
  - [ ] Complete Authentik service configuration
  - [ ] Test SSO functionality
  - [ ] Configure forward authentication

#### ✅ **Recently Fixed**
- [x] **Build Issues**
  - [x] Fixed Redis configuration warnings (updated option names)
  - [x] Removed nslookup package (not available)
  - [x] Fixed Grafana provisioning configuration
  - [x] Added default values for required options
  - [x] All flake configurations now build successfully

- [x] **Deployment Tools**
  - [x] Created `scripts/deploy-test.sh` for building and testing configurations
  - [x] Created `scripts/generate-lxc.sh` for generating Proxmox LXC images
  - [x] Created comprehensive `DEPLOYMENT.md` guide
  - [x] All containers can be built and tested successfully

#### 🔧 **Medium Priority**
- [ ] **Build Optimization**
  - [ ] Reduce build times
  - [ ] Optimize container images
  - [ ] Parallel builds
  - [ ] Caching strategies

- [ ] **Documentation**
  - [ ] Deployment guide
  - [ ] Configuration reference
  - [ ] Troubleshooting guide
  - [ ] API documentation

### 📊 **Progress Tracking**

#### **Phase 1: Core Infrastructure**
- **Status**: ✅ COMPLETED
- **Progress**: 100% (5/5 modules)
- **Next**: Move to Phase 2

#### **Phase 2: Service Modules**
- **Status**: 🔄 IN PROGRESS
- **Progress**: 0% (0/5 modules)
- **Next**: Start with Mail module

#### **Phase 3: Management Plane**
- **Status**: 📋 PLANNED
- **Progress**: 0% (0/2 components)
- **Next**: Begin after Phase 2 completion

#### **Phase 4: Advanced Features**
- **Status**: 📋 PLANNED
- **Progress**: 0% (0/4 features)
- **Next**: Begin after Phase 3 completion

### 🎯 **Next Actions**

1. **Immediate (This Week)**
   - [ ] Fix remaining build issues
   - [ ] Complete Authentik integration
   - [ ] Start Mail module implementation

2. **Short Term (Next 2 Weeks)**
   - [ ] Complete all service modules
   - [ ] Test container deployments
   - [ ] Begin management plane development

3. **Medium Term (Next Month)**
   - [ ] Complete management plane
   - [ ] Implement backup automation
   - [ ] Add advanced monitoring

### 📝 **Notes**

- **Build Issues**: ✅ All build issues resolved - Redis configuration warnings fixed, nslookup package removed, Grafana provisioning simplified
- **Authentication**: Authentik module needs proper integration with authentik-nix
- **Testing**: ✅ Ready for SSH testing - all containers build successfully, deployment tools created
- **Performance**: Build times are currently slow, need optimization
- **TODO Tracking**: ✅ Comprehensive TODO system implemented with progress tracking
- **Deployment**: ✅ Deployment guide and scripts created for easy testing

---

**Last Updated**: 2024-11-13
**Current Focus**: Phase 2 - Service Modules
**Next Milestone**: Complete Mail module 