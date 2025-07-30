# NixMox - NixOS LXC Orchestration on Proxmox

NixMox is a highly automated self-hosting platform using NixOS containers on Proxmox VE. It provides a modular, declarative, and user-friendly way to run dozens of self-hosted services with single sign-on and unified management.

## Project Status

This is the initial scaffolding phase. The core NixOS flake implementation is being built with the following components:

**📊 Progress Tracking**: See [TODO.md](TODO.md) for detailed progress tracking and upcoming tasks.

### ✅ Completed
- Basic flake structure with multi-container support
- Common module for shared configuration
- Authentik module for SSO
- Caddy reverse proxy module with forward auth
- Monitoring module (Prometheus + Grafana)
- SOPS integration for secrets management
- Development shell with necessary tools

### 🚧 In Progress
- Service-specific modules (mail, media, nextcloud, etc.)
- Container image generation
- Proxmox integration

### 📋 Planned
- Go backend for management
- React frontend
- Service discovery and DNS
- Backup automation
- Complete service catalog

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Proxmox VE   │    │   NixMox Flake  │    │  Management UI  │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Authentik   │ │    │ │ Common      │ │    │ │ Go Backend  │ │
│ │ Container   │ │    │ │ Module      │ │    │ │             │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Caddy Proxy │ │    │ │ Service     │ │    │ │ React UI    │ │
│ │ Container   │ │    │ │ Modules     │ │    │ │             │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │                 │
│ │ Monitoring  │ │    │ │ SOPS        │ │    │                 │
│ │ Container   │ │    │ │ Secrets     │ │    │                 │
│ └─────────────┘ │    │ └─────────────┘ │    │                 │
│ ┌─────────────┐ │    │                 │    │                 │
│ │ Service     │ │    │                 │    │                 │
│ │ Containers  │ │    │                 │    │                 │
│ └─────────────┘ │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Quick Start

### Prerequisites

1. **Nix with Flakes**: Ensure you have Nix installed with flakes enabled
2. **Proxmox VE**: A Proxmox host or cluster
3. **SSH Access**: Key-based SSH access to Proxmox host

### Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/devnullvoid/nixmox.git
   cd nixmox
   ```

2. **Enter the development shell**:
   ```bash
   nix develop
   ```

3. **Build a container configuration**:
   ```bash
   # Build the Authentik container
   nix build .#nixosConfigurations.authentik.config.system.build.toplevel
   
   # Build the Caddy container
   nix build .#nixosConfigurations.caddy.config.system.build.toplevel
   ```

4. **Generate container images**:
   ```bash
   # Generate Proxmox LXC image for Authentik
   nixos-generators -f proxmox-lxc -c ./configuration.nix
   ```

### Container Structure

Each container is defined as a NixOS configuration:

- **authentik**: Identity provider and SSO
- **caddy**: Reverse proxy with forward auth
- **monitoring**: Prometheus + Grafana
- **mail**: Mail server (planned)
- **media**: Jellyfin + Arr stack (planned)
- **nextcloud**: File sharing (planned)
- **vaultwarden**: Password manager (planned)
- **dns**: Unbound DNS server (planned)

### Configuration

The flake uses a modular approach:

- `modules/common/`: Shared configuration for all containers
- `modules/authentik/`: Authentik-specific configuration
- `modules/caddy/`: Caddy reverse proxy configuration
- `modules/monitoring/`: Prometheus + Grafana configuration
- `secrets/`: SOPS-encrypted secrets (template provided)

### Secrets Management

1. **Set up SOPS**:
   ```bash
   # Generate age key
   age-keygen -o secrets/age.key
   
   # Create .sops.yaml
   cat > .sops.yaml << EOF
   keys:
     - &nixmox age1...
   creation_rules:
     - path_regex: \.yaml$
       key_groups:
       - age:
         - *nixmox
   EOF
   ```

2. **Encrypt secrets**:
   ```bash
   sops -e -i secrets/default.yaml
   ```

### Network Configuration

The default network configuration uses:
- **Internal Network**: `192.168.50.0/24`
- **Gateway**: `192.168.50.1`
- **Domain**: `nixmox.lan`

Container IP assignments:
- `authentik`: `192.168.50.2`
- `caddy`: `192.168.50.3`
- `monitoring`: `192.168.50.4`
- `mail`: `192.168.50.5`
- `media`: `192.168.50.10`
- `nextcloud`: `192.168.50.11`
- `vaultwarden`: `192.168.50.12`
- `dns`: `192.168.50.13`

## Development

### Adding a New Service

1. **Create a new module**:
   ```bash
   mkdir modules/myservice
   ```

2. **Create the module configuration**:
   ```nix
   # modules/myservice/default.nix
   { config, lib, pkgs, ... }:
   {
     options.services.nixmox.myservice = {
       enable = mkEnableOption "My Service";
       # Add your options here
     };
   
     config = mkIf cfg.enable {
       # Add your service configuration here
     };
   }
   ```

3. **Add to the flake**:
   ```nix
   # In flake.nix, add to containers
   myservice = { config, pkgs, lib, ... }: {
     imports = [
       commonConfig
       ./modules/myservice
     ];
     networking.hostName = "myservice";
     services.nixmox.myservice.enable = true;
   };
   ```

### Testing

1. **Build the configuration**:
   ```bash
   nix build .#nixosConfigurations.myservice.config.system.build.toplevel
   ```

2. **Generate container image**:
   ```bash
   nixos-generators -f proxmox-lxc -c ./configuration.nix
   ```

## Roadmap

### Phase 1: Core Infrastructure ✅
- [x] Basic flake structure
- [x] Common module
- [x] Authentik integration
- [x] Caddy reverse proxy
- [x] Monitoring stack

### Phase 2: Service Modules 🚧
- [ ] Mail server (Simple NixOS Mailserver)
- [ ] Media stack (Jellyfin + Arr)
- [ ] Nextcloud
- [ ] Vaultwarden
- [ ] DNS server (Unbound)

### Phase 3: Management Plane 📋
- [ ] Go backend
- [ ] React frontend
- [ ] Proxmox API integration
- [ ] Service deployment automation

### Phase 4: Advanced Features 📋
- [ ] Backup automation (Restic)
- [ ] Service discovery
- [ ] Multi-environment support
- [ ] Advanced monitoring

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `nix build`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [VGHS-lucaruby's NixOS-Server](https://github.com/VGHS-lucaruby/nixos-server) for inspiration
- [Authentik Nix](https://github.com/nix-community/authentik-nix) for the Authentik module
- [SOPS-Nix](https://github.com/Mic92/sops-nix) for secrets management
- [NixOS Generators](https://github.com/nix-community/nixos-generators) for container images 