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

# Create CA configuration file with proper extensions
cat > "$CA_DIR/ca-extensions.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = NixMox
CN = NixMox Internal CA

[v3_ca]
# Basic constraints - this is a CA
basicConstraints = critical,CA:TRUE

# Key usage - what the CA key can be used for
keyUsage = critical,keyCertSign,cRLSign

# Subject key identifier - for CA chaining
subjectKeyIdentifier = hash

# Authority key identifier - for CA chaining
authorityKeyIdentifier = keyid:always,issuer

# Certificate policies - custom OID for NixMox internal CA
certificatePolicies = 1.3.6.1.4.1.99999.1.1.1

# CRL distribution points (optional - can be enabled later)
# crlDistributionPoints = URI:http://crl.nixmox.lan/ca.crl

# Authority Information Access (optional - for OCSP)
# authorityInfoAccess = OCSP;URI:http://ocsp.nixmox.lan
EOF

# Generate CA certificate with proper extensions
openssl req -new -x509 -days 3650 -key "$CA_DIR/$CA_NAME.key" \
  -out "$CA_DIR/$CA_NAME.crt" -config "$CA_DIR/ca-extensions.cnf"

# Generate wildcard certificate for all services
echo "Generating wildcard certificate for *.nixmox.lan..."
openssl genrsa -out "$CA_DIR/wildcard-nixmox-lan.key" 2048

# Create OpenSSL configuration file with SANs
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
# Key usage for server certificates
keyUsage = critical,digitalSignature,keyEncipherment,dataEncipherment

# Extended key usage for TLS server and client authentication
extendedKeyUsage = serverAuth,clientAuth

# Subject Alternative Names
subjectAltName = @alt_names

# Basic constraints - not a CA
basicConstraints = CA:FALSE

# Subject key identifier
subjectKeyIdentifier = hash

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

# Generate CSR with SANs
openssl req -new -key "$CA_DIR/wildcard-nixmox-lan.key" \
  -out "$CA_DIR/wildcard-nixmox-lan.csr" \
  -config "$CA_DIR/openssl-san.cnf"

# Sign wildcard certificate with CA and include SANs
echo "Signing wildcard certificate with CA and SANs..."
openssl x509 -req -days 365 -in "$CA_DIR/wildcard-nixmox-lan.csr" \
  -CA "$CA_DIR/$CA_NAME.crt" -CAkey "$CA_DIR/$CA_NAME.key" \
  -CAcreateserial -out "$CA_DIR/wildcard-nixmox-lan.crt" \
  -extfile "$CA_DIR/openssl-san.cnf" -extensions v3_req

# Create CA bundle for containers
echo "Creating CA bundle for containers..."
cat "$CA_DIR/$CA_NAME.crt" > "$CA_DIR/ca-bundle.crt"

# Verify CA certificate extensions
echo "Verifying CA certificate extensions..."
echo "CA Certificate Extensions:"
openssl x509 -in "$CA_DIR/$CA_NAME.crt" -text -noout | grep -A 10 "X509v3 extensions" || echo "No extensions found"

echo ""
echo "Wildcard Certificate Extensions:"
openssl x509 -in "$CA_DIR/wildcard-nixmox-lan.crt" -text -noout | grep -A 10 "X509v3 extensions" || echo "No extensions found"

# Clean up temporary files
rm "$CA_DIR/wildcard-nixmox-lan.csr"
rm "$CA_DIR/openssl-san.cnf"
rm "$CA_DIR/ca-extensions.cnf"

# Set proper permissions
chmod 600 "$CA_DIR/$CA_NAME.key"
chmod 600 "$CA_DIR/wildcard-nixmox-lan.key"
chmod 644 "$CA_DIR/$CA_NAME.crt"
chmod 644 "$CA_DIR/wildcard-nixmox-lan.crt"
chmod 644 "$CA_DIR/ca-bundle.crt"

echo ""
echo "✅ CA and wildcard certificate with proper extensions generated successfully in $CA_DIR/"
echo ""
echo "Files created:"
echo "  - $CA_DIR/$CA_NAME.key (CA private key - keep secure!)"
echo "  - $CA_DIR/$CA_NAME.crt (CA certificate with proper key usage extensions - distribute to all hosts)"
echo "  - $CA_DIR/wildcard-nixmox-lan.key (Wildcard private key)"
echo "  - $CA_DIR/wildcard-nixmox-lan.crt (Wildcard certificate with SANs and proper extensions for *.nixmox.lan)"
echo "  - $CA_DIR/ca-bundle.crt (CA bundle for containers)"
echo ""
echo "SANs included:"
echo "  - *.nixmox.lan (wildcard)"
echo "  - nixmox.lan"
echo "  - auth.nixmox.lan"
echo "  - git.nixmox.lan"
echo "  - authentik.nixmox.lan"
echo "  - *.auth.nixmox.lan"
echo "  - *.git.nixmox.lan"
echo "  - *.authentik.nixmox.lan"
echo ""
echo "CA Extensions included:"
echo "  - basicConstraints: CA:TRUE"
echo "  - keyUsage: keyCertSign, cRLSign"
echo "  - subjectKeyIdentifier: hash"
echo "  - authorityKeyIdentifier: keyid:always,issuer"
echo "  - certificatePolicies: 1.3.6.1.4.1.99999.1.1.1"
echo ""
echo "Next steps:"
echo "  1. Add $CA_DIR/ to .gitignore (contains private keys)"
echo "  2. Copy $CA_NAME.crt to all NixOS hosts"
echo "  3. Update Caddy configuration to use our internal CA"
echo "  4. Update container configurations to trust the CA"
echo "  5. Restart services using the new certificate"
