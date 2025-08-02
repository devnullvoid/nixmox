# SOPS Setup Guide for NixMox

This guide explains how to set up SOPS (Secrets OPerationS) for encrypted secrets management in NixMox.

## 🔐 What is SOPS?

SOPS is Mozilla's tool for encrypting and decrypting files containing secrets. It integrates seamlessly with NixOS through the `sops-nix` module.

## 📋 Prerequisites

1. **Install SOPS**:
   ```bash
   # On NixOS
   nix-env -iA nixpkgs.sops

   # On other systems
   nix-env -iA nixpkgs.sops
   ```

2. **Install age** (for key generation):
   ```bash
   nix-env -iA nixpkgs.age
   ```

## 🔑 Step 1: Generate Age Keys

### Generate Master Key
```bash
# Generate age key pair
age-keygen -o ~/.config/sops/age/keys.txt

# Display public key (add this to .sops.yaml)
cat ~/.config/sops/age/keys.txt | grep "public key"
```

### Generate Service Keys (Optional)
```bash
# Generate separate keys for different environments
age-keygen -o ~/.config/sops/age/production.txt
age-keygen -o ~/.config/sops/age/staging.txt
```

## 📝 Step 2: Configure SOPS

### Create .sops.yaml
```yaml
# .sops.yaml
creation_rules:
  - path_regex: \.yaml$
    age: >-
      age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
      age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### Update secrets/default.yaml
1. **Add your SSH public keys**:
   ```yaml
   nixmox:
     ssh_authorized_keys:
       - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-key-here"
   ```

2. **Add your age public key**:
   ```yaml
   nixmox:
     age_key: "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p"
   ```

## 🔒 Step 3: Encrypt Secrets

```bash
# Encrypt the secrets file
sops -e -i secrets/default.yaml

# Verify encryption
sops -d secrets/default.yaml
```

## ⚙️ Step 4: Configure NixOS

### Update flake.nix
The flake already includes sops-nix, but verify:
```nix
inputs = {
  sops-nix.url = "github:Mic92/sops-nix";
  # ...
};
```

### Update modules/common/default.nix
```nix
# Add SOPS configuration
sops.defaultSopsFile = ../../secrets/default.yaml;
sops.age.keyFile = "/path/to/age/key.txt";  # Set this path
```

## 🚀 Step 5: Deploy

```bash
# Deploy with encrypted secrets
./scripts/deploy-remote.sh authentik YOUR_CONTAINER_IP
```

## 🔧 Troubleshooting

### Common Issues

1. **Age key not found**:
   ```bash
   # Check age key location
   ls -la ~/.config/sops/age/
   
   # Update sops.age.keyFile path in flake.nix
   ```

2. **SOPS not installed**:
   ```bash
   # Install on remote host
   nix-env -iA nixpkgs.sops
   ```

3. **Permission denied**:
   ```bash
   # Fix age key permissions
   chmod 600 ~/.config/sops/age/keys.txt
   ```

## 📚 Advanced Configuration

### Multiple Environments
```yaml
# .sops.yaml
creation_rules:
  - path_regex: production\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
  - path_regex: staging\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### Key Rotation
```bash
# Generate new key
age-keygen -o ~/.config/sops/age/new-key.txt

# Re-encrypt with new key
sops -e -i secrets/default.yaml
```

## 🔐 Security Best Practices

1. **Never commit unencrypted secrets**
2. **Use different keys for different environments**
3. **Rotate keys regularly**
4. **Backup age keys securely**
5. **Use strong passwords for all services**

## 📖 Next Steps

1. **Add your SSH public keys** to `secrets/default.yaml`
2. **Generate age keys** and update `.sops.yaml`
3. **Encrypt the secrets file** with `sops -e -i secrets/default.yaml`
4. **Deploy and test** the configuration 