#!/bin/bash

set -e

# Configuration
CA_DIR="certs"
CA_NAME="nixmox-internal-ca"
CA_SUBJECT="/C=US/ST=State/L=City/O=NixMox/CN=NixMox Internal CA"
WILDCARD_SUBJECT="/C=US/ST=State/L=City/O=NixMox/CN=*.nixmox.lan"

echo "Generating NixMox internal CA and wildcard certificate..."

# Create certificates directory
mkdir -p "$CA_DIR"

# Generate CA private key and certificate
echo "Generating CA private key and certificate..."
openssl genrsa -out "$CA_DIR/$CA_NAME.key" 4096
openssl req -new -x509 -days 3650 -key "$CA_DIR/$CA_NAME.key" \
  -out "$CA_DIR/$CA_NAME.crt" -subj "$CA_SUBJECT"

# Generate wildcard certificate for all services
echo "Generating wildcard certificate for *.nixmox.lan..."
openssl genrsa -out "$CA_DIR/wildcard-nixmox-lan.key" 2048
openssl req -new -key "$CA_DIR/wildcard-nixmox-lan.key" \
  -out "$CA_DIR/wildcard-nixmox-lan.csr" \
  -subj "$WILDCARD_SUBJECT"

# Sign wildcard certificate with CA
echo "Signing wildcard certificate with CA..."
openssl x509 -req -days 365 -in "$CA_DIR/wildcard-nixmox-lan.csr" \
  -CA "$CA_DIR/$CA_NAME.crt" -CAkey "$CA_DIR/$CA_NAME.key" \
  -CAcreateserial -out "$CA_DIR/wildcard-nixmox-lan.crt"

# Create CA bundle for containers
echo "Creating CA bundle for containers..."
cat "$CA_DIR/$CA_NAME.crt" > "$CA_DIR/ca-bundle.crt"

# Clean up CSR
rm "$CA_DIR/wildcard-nixmox-lan.csr"

# Set proper permissions
chmod 600 "$CA_DIR/$CA_NAME.key"
chmod 600 "$CA_DIR/wildcard-nixmox-lan.key"
chmod 644 "$CA_DIR/$CA_NAME.crt"
chmod 644 "$CA_DIR/wildcard-nixmox-lan.crt"
chmod 644 "$CA_DIR/ca-bundle.crt"

echo ""
echo "✅ CA and wildcard certificate generated successfully in $CA_DIR/"
echo ""
echo "Files created:"
echo "  - $CA_DIR/$CA_NAME.key (CA private key - keep secure!)"
echo "  - $CA_DIR/$CA_NAME.crt (CA certificate - distribute to all hosts)"
echo "  - $CA_DIR/wildcard-nixmox-lan.key (Wildcard private key)"
echo "  - $CA_DIR/wildcard-nixmox-lan.crt (Wildcard certificate for *.nixmox.lan)"
echo "  - $CA_DIR/ca-bundle.crt (CA bundle for containers)"
echo ""
echo "Next steps:"
echo "  1. Add $CA_DIR/ to .gitignore (contains private keys)"
echo "  2. Copy $CA_NAME.crt to all NixOS hosts"
echo "  3. Update Caddy configuration to use our internal CA"
echo "  4. Update container configurations to trust the CA"
