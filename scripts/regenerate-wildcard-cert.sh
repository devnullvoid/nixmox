#!/bin/bash

set -e

# Configuration
CA_DIR="certs"
CA_NAME="nixmox-internal-ca"
WILDCARD_NAME="wildcard-nixmox-lan"

echo "Regenerating wildcard certificate with SANs (keeping existing CA)..."
echo "This will fix JWT signing issues for OIDC/OAuth2 services."
echo ""

# Check if CA exists
if [ ! -f "$CA_DIR/$CA_NAME.crt" ] || [ ! -f "$CA_DIR/$CA_NAME.key" ]; then
    echo "❌ Error: CA certificate or key not found in $CA_DIR/"
    echo "   Please ensure $CA_DIR/$CA_NAME.crt and $CA_DIR/$CA_NAME.key exist"
    exit 1
fi

# Check if wildcard key exists
if [ ! -f "$CA_DIR/$WILDCARD_NAME.key" ]; then
    echo "❌ Error: Wildcard private key not found in $CA_DIR/$WILDCARD_NAME.key"
    echo "   Please ensure the wildcard private key exists"
    exit 1
fi

echo "✅ Found existing CA: $CA_DIR/$CA_NAME.crt"
echo "✅ Found existing wildcard key: $CA_DIR/$WILDCARD_NAME.key"
echo ""

# Backup existing wildcard certificate
if [ -f "$CA_DIR/$WILDCARD_NAME.crt" ]; then
    echo "📋 Backing up existing wildcard certificate..."
    cp "$CA_DIR/$WILDCARD_NAME.crt" "$CA_DIR/$WILDCARD_NAME.crt.backup-$(date +%Y%m%d-%H%M%S)"
    echo "   Backup created: $CA_DIR/$WILDCARD_NAME.crt.backup-$(date +%Y%m%d-%H%M%S)"
    echo ""
fi

# Create OpenSSL configuration file with SANs
echo "🔧 Creating OpenSSL configuration with SANs..."
cat > "$CA_DIR/openssl-san.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = NixMox
CN = *.nixmox.lan

[v3_req]
keyUsage = digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.nixmox.lan
DNS.2 = nixmox.lan
DNS.3 = auth.nixmox.lan
DNS.4 = git.nixmox.lan
DNS.5 = authentik.nixmox.lan
DNS.6 = *.auth.nixmox.lan
DNS.7 = *.git.nixmox.lan
DNS.8 = *.authentik.nixmox.lan
EOF

# Generate new CSR with SANs using existing key
echo "🔑 Generating new CSR with SANs using existing wildcard key..."
openssl req -new -key "$CA_DIR/$WILDCARD_NAME.key" \
  -out "$CA_DIR/$WILDCARD_NAME.csr" \
  -config "$CA_DIR/openssl-san.cnf"

# Sign new wildcard certificate with existing CA and include SANs
echo "✍️  Signing new wildcard certificate with existing CA and SANs..."
openssl x509 -req -days 365 -in "$CA_DIR/$WILDCARD_NAME.csr" \
  -CA "$CA_DIR/$CA_NAME.crt" -CAkey "$CA_DIR/$CA_NAME.key" \
  -CAcreateserial -out "$CA_DIR/$WILDCARD_NAME.crt" \
  -extfile "$CA_DIR/openssl-san.cnf" -extensions v3_req

# Clean up temporary files
echo "🧹 Cleaning up temporary files..."
rm "$CA_DIR/$WILDCARD_NAME.csr"
rm "$CA_DIR/openssl-san.cnf"

# Set proper permissions
chmod 644 "$CA_DIR/$WILDCARD_NAME.crt"

echo ""
echo "✅ Wildcard certificate with SANs regenerated successfully!"
echo "   This fixes JWT signing issues for OIDC/OAuth2 services."
echo ""
echo "Files updated:"
echo "  - $CA_DIR/$WILDCARD_NAME.crt (New wildcard certificate with SANs)"
echo "  - $CA_DIR/$WILDCARD_NAME.crt.backup-* (Backup of old certificate)"
echo ""
echo "SANs included in new certificate:"
echo "  - *.nixmox.lan (wildcard)"
echo "  - nixmox.lan"
echo "  - auth.nixmox.lan"
echo "  - git.nixmox.lan"
echo "  - authentik.nixmox.lan"
echo "  - *.auth.nixmox.lan"
echo "  - *.git.nixmox.lan"
echo "  - *.authentik.nixmox.lan"
echo ""
echo "Next steps:"
echo "  1. Copy the new wildcard certificate to your services"
echo "  2. Restart services using the certificate (Caddy, etc.)"
echo "  3. Test the OIDC setup in Guacamole"
echo ""
echo "Note: Your existing CA ($CA_DIR/$CA_NAME.crt) was preserved and reused."
