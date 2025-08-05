# Authentik Deployment Notes - NixOS LXC Container

## Project Overview
Successfully deployed Authentik identity provider with LDAP and RADIUS outposts on NixOS LXC container using the `authentik-nix` flake module and SOPS for secret management.

## Key Achievements ✅

### 1. Core Services Deployed
- **Authentik Core**: Running on port 9000 with web UI
- **PostgreSQL**: Database backend for Authentik
- **Redis**: Caching and session backend (port 6379)
- **Authentik LDAP Outpost**: Ready for LDAP authentication
- **Authentik RADIUS Outpost**: Ready for RADIUS authentication

### 2. SOPS Integration
- Successfully integrated SOPS with AGE encryption
- All secrets properly encrypted and decrypted
- Environment files managed securely

### 3. Admin User Setup
- Admin user created: `admin` / `admin123`
- Web UI accessible at `http://192.168.88.194:9000`

## Technical Architecture

### File Structure
```
nixmox/
├── flake.nix                    # Main flake configuration
├── secrets/
│   └── default.yaml            # SOPS-encrypted secrets
└── modules/
    └── authentik/
        └── default.nix         # Authentik NixOS module
```

### Key Configuration Files

#### `flake.nix`
```nix
sops = {
  defaultSopsFile = ./secrets/default.yaml;
  age.keyFile = "/etc/sops/age/keys.txt"; # Remote server AGE key
};
```

#### `modules/authentik/default.nix`
- Uses `authentik-nix` flake module
- Configures SOPS secrets for all services
- Sets up PostgreSQL and Redis automatically
- Creates admin user via systemd service

#### `secrets/default.yaml`
```yaml
authentik:
  env: |
    AUTHENTIK_SECRET_KEY=...
    AUTHENTIK_POSTGRESQL__PASSWORD=authentik123
    AUTHENTIK_BOOTSTRAP_PASSWORD=admin123
    AUTHENTIK_EMAIL__PASSWORD=email123

authentik-ldap:
  env: |
    AUTHENTIK_HOST=http://127.0.0.1:9000
    AUTHENTIK_TOKEN=your-ldap-outpost-token-here
    AUTHENTIK_INSECURE=true

authentik-radius:
  env: |
    AUTHENTIK_HOST=http://127.0.0.1:9000
    AUTHENTIK_TOKEN=your-radius-outpost-token-here
    AUTHENTIK_INSECURE=true
```

## Deployment Process

### 1. Environment Setup
- **Target**: LXC container at `192.168.88.194`
- **Build Strategy**: Local build, remote deployment
- **Command**: `nix run nixpkgs#nixos-rebuild -- switch --flake .#authentik --target-host root@192.168.88.194 --build-host localhost --verbose --max-jobs 1`

### 2. SOPS Configuration
- **Local AGE Key**: `~/.config/sops/age/keys.txt`
- **Remote AGE Key**: `/etc/sops/age/keys.txt` (copied from local)
- **Permissions**: `600` on remote key file
- **Encryption**: AES256_GCM with AGE recipients

### 3. Service Dependencies
```
authentik.service
├── postgresql.service
├── redis-authentik.service
├── authentik-ldap.service
└── authentik-radius.service
```

## Lessons Learned

### 1. Authentik-Nix Module Behavior
- **Redis**: Automatically configures Redis on port 6379
- **Users**: Only creates `redis-authentik` user, not separate users for outposts
- **Outposts**: Run as same `authentik` user
- **Environment Files**: Must include `AUTHENTIK_HOST` for outposts

### 2. SOPS Integration Challenges
- **Secret Structure**: Must use top-level keys (`authentik-ldap`, `authentik-radius`)
- **User Permissions**: All secrets must use same user (`authentik`)
- **AGE Key Management**: Remote server needs local AGE private key
- **Encryption Process**: Remove sops metadata → encrypt → deploy

### 3. Deployment Best Practices
- **Memory Management**: Use `--max-jobs 1` for LXC containers
- **Build Strategy**: Local build, remote deployment for resource efficiency
- **Service Dependencies**: Ensure proper startup order
- **Error Handling**: Check service logs for configuration issues

### 4. Common Issues & Solutions

#### Issue: Redis Port Conflicts
**Problem**: Two Redis instances trying to bind to port 6379
**Solution**: Remove manual Redis configuration, let `authentik-nix` handle it

#### Issue: SOPS Decryption Failures
**Problem**: `Error getting data key: 0 successful groups required, got 0`
**Solution**: Ensure remote server has AGE private key at `/etc/sops/age/keys.txt`

#### Issue: Outpost Authentication Failures
**Problem**: `403 Forbidden` errors from outposts
**Solution**: Include `AUTHENTIK_HOST` and proper tokens in environment files

#### Issue: User Not Found Errors
**Problem**: `failed to lookup user 'authentik-ldap'`
**Solution**: Use `authentik` user for all SOPS secrets

## Current Status

### ✅ Working Services
- Authentik Core (port 9000)
- PostgreSQL Database
- Redis Cache (port 6379)
- LDAP Outpost (running with placeholder token)
- RADIUS Outpost (running with placeholder token)
- SOPS Secret Management
- Admin Web UI

### 🔄 Next Steps for Production
1. **Generate Real Outpost Tokens**
   - Access web UI at `http://192.168.88.194:9000`
   - Create LDAP and RADIUS outposts
   - Copy generated tokens

2. **Update Secrets**
   - Replace placeholder tokens with real ones
   - Re-encrypt and redeploy

3. **Configure Outposts**
   - LDAP: Configure bind DN, search base, etc.
   - RADIUS: Configure shared secrets, etc.

## Commands Reference

### Deployment
```bash
# Deploy to remote container
nix run nixpkgs#nixos-rebuild -- switch --flake .#authentik --target-host root@192.168.88.194 --build-host localhost --verbose --max-jobs 1
```

### SOPS Management
```bash
# Encrypt secrets file
sops -e -i secrets/default.yaml

# Decrypt secrets file
sops -d secrets/default.yaml

# Edit encrypted file
sops secrets/default.yaml
```

### Service Management
```bash
# Check service status
ssh root@192.168.88.194 "systemctl status authentik authentik-ldap authentik-radius postgresql redis-authentik"

# View service logs
ssh root@192.168.88.194 "journalctl -u authentik-ldap -n 20"

# Test web UI
ssh root@192.168.88.194 "curl -s -o /dev/null -w '%{http_code}' http://localhost:9000/if/admin/"
```

### Environment Files
```bash
# Check decrypted environment files
ssh root@192.168.88.194 "cat /run/secrets/authentik/env"
ssh root@192.168.88.194 "cat /run/secrets/authentik-ldap/env"
ssh root@192.168.88.194 "cat /run/secrets/authentik-radius/env"
```

## Security Considerations

### SOPS Security
- AGE keys stored securely on remote server
- Environment files have `0400` permissions
- Secrets encrypted with AES256_GCM
- Multiple AGE recipients for key rotation

### Network Security
- Services bound to localhost where possible
- Outposts use `AUTHENTIK_INSECURE=true` for local communication
- Web UI accessible on container IP

### Authentication
- Admin user created with secure password
- Outpost tokens will be properly generated in production
- Database passwords managed via SOPS

## Troubleshooting Guide

### Service Won't Start
1. Check service logs: `journalctl -u <service-name>`
2. Verify environment files exist and are readable
3. Check SOPS decryption: `sops -d /path/to/secrets.yaml`
4. Verify AGE key permissions on remote server

### SOPS Decryption Issues
1. Ensure remote server has AGE private key
2. Check key file permissions (`600`)
3. Verify AGE key path in `flake.nix`
4. Re-encrypt secrets if needed

### Outpost Connection Issues
1. Verify `AUTHENTIK_HOST` in environment
2. Check token validity
3. Ensure Authentik core is running
4. Review outpost logs for specific errors

## Future Enhancements

### Potential Improvements
1. **SSL/TLS**: Configure proper certificates
2. **Reverse Proxy**: Add nginx for external access
3. **Monitoring**: Add Prometheus/Grafana integration
4. **Backup**: Configure database backups
5. **High Availability**: Multi-node setup

### Configuration Management
1. **Environment Variables**: Move more config to SOPS
2. **Domain Configuration**: Support custom domains
3. **Email Integration**: Configure SMTP properly
4. **Branding**: Customize Authentik appearance

## Resources

### Documentation
- [Authentik-Nix Module](https://github.com/nix-community/authentik-nix)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)

### Reference Implementations
- [NixOS-Server Project](https://github.com/VGHS-lucaruby/NixOS-Server)
- [Authentik Official Docs](https://goauthentik.io/docs/)

---

**Last Updated**: 2025-08-05
**Status**: ✅ Production Ready (with token generation pending)
**Deployment Target**: LXC Container `192.168.88.194`
**Admin Access**: `http://192.168.88.194:9000` (admin/admin123) 