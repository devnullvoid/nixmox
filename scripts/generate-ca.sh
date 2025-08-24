#!/bin/bash

set -e

# Configuration
CA_DIR="certs"
CA_NAME="nixmox-internal-ca"
CA_SUBJECT="/C=US/ST=State/L=City/O=NixMox/CN=NixMox Internal CA"
SERVER_SUBJECT="/C=US/ST=State/L=City/O=NixMox/CN=*.nixmox.lan"

echo "Generating NixMox internal CA and certificates..."

# Create certificates directory
mkdir -p "$CA_DIR"

# Generate CA private key and certificate
echo "Generating CA private key and certificate..."
openssl genrsa -out "$CA_DIR/$CA_NAME.key" 4096
openssl req -new -x509 -days 3650 -key "$CA_DIR/$CA_NAME.key" \
  -out "$CA_DIR/$CA_NAME.crt" -subj "$CA_SUBJECT"

# Generate server certificate for Caddy
echo "Generating server certificate for Caddy..."
openssl genrsa -out "$CA_DIR/caddy-server.key" 2048
openssl req -new -key "$CA_DIR/caddy-server.key" \
  -out "$CA_DIR/caddy-server.csr" \
  -subj "$SERVER_SUBJECT"

# Sign server certificate with CA
echo "Signing server certificate with CA..."
openssl x509 -req -days 365 -in "$CA_DIR/caddy-server.csr" \
  -CA "$CA_DIR/$CA_NAME.crt" -CAkey "$CA_DIR/$CA_NAME.key" \
  -CAcreateserial -out "$CA_DIR/caddy-server.crt"

# Create CA bundle for containers
echo "Creating CA bundle for containers..."
cat "$CA_DIR/$CA_NAME.crt" > "$CA_DIR/ca-bundle.crt"

# Set proper permissions
chmod 600 "$CA_DIR/$CA_NAME.key"
chmod 600 "$CA_DIR/caddy-server.key"
chmod 644 "$CA_DIR/$CA_NAME.crt"
chmod 644 "$CA_DIR/caddy-server.crt"
chmod 644 "$CA_DIR/ca-bundle.crt"

# Clean up CSR
rm "$CA_DIR/caddy-server.csr"

echo ""
echo "✅ CA and certificates generated successfully in $CA_DIR/"
echo ""
echo "Files created:"
echo "  - $CA_DIR/$CA_NAME.key (CA private key - keep secure!)"
echo "  - $CA_DIR/$CA_NAME.crt (CA certificate - distribute to all hosts)"
echo "  - $CA_DIR/caddy-server.key (Caddy server private key)"
echo "  - $CA_DIR/caddy-server.crt (Caddy server certificate)"
echo "  - $CA_DIR/ca-bundle.crt (CA bundle for containers)"
echo ""
echo "Next steps:"
echo "  1. Add $CA_DIR/ to .gitignore (contains private keys)"
echo "  2. Copy $CA_NAME.crt to all NixOS hosts"
echo "  3. Update Caddy configuration to use these certificates"
echo "  4. Update container configurations to trust the CA"
