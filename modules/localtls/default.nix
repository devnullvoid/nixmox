{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixmox.localtls;
in {
  options.services.nixmox.localtls = {
    enable = mkEnableOption "Generate and trust a local CA and server certificate";

    domains = mkOption {
      type = with types; listOf str;
      default = [];
      description = "DNS names to include as SANs in the self-signed certificate (first used as CN).";
    };

    caddyCertDir = mkOption {
      type = types.str;
      default = "/etc/caddy/tls";
      description = "Where to install server cert/key for Caddy.";
    };
  };

  config = mkIf cfg.enable (let
    domains = cfg.domains;
    primary = if domains == [] then "localhost" else builtins.head domains;
    sanEntries = lib.imap0 (idx: d: "DNS." + toString (idx + 1) + " = " + d) domains;
    sanText = builtins.concatStringsSep "\n" sanEntries;
    certs = pkgs.runCommand "local-ca-and-cert" { buildInputs = [ pkgs.openssl ]; } ''
      set -eu
      mkdir -p $out
      # CA
      openssl req -x509 -new -nodes -newkey rsa:2048 -sha256 -days 3650 \
        -subj "/CN=NixMox Local CA" \
        -keyout $out/ca.key -out $out/ca.crt
      # Server key
      openssl genrsa -out $out/server.key 2048
      # CSR config
      cat > $out/openssl.cnf <<CFG
      [ req ]
      distinguished_name = dn
      req_extensions = v3_req
      [ dn ]
      [ v3_req ]
      basicConstraints = CA:FALSE
      keyUsage = digitalSignature, keyEncipherment
      subjectAltName = @alt_names
      [ alt_names ]
      ${sanText}
      CFG
      # CSR
      openssl req -new -key $out/server.key -subj "/CN=${primary}" -out $out/server.csr -config $out/openssl.cnf
      # Sign
      openssl x509 -req -in $out/server.csr -CA $out/ca.crt -CAkey $out/ca.key -CAcreateserial -out $out/server.crt -days 825 -sha256 -extfile $out/openssl.cnf -extensions v3_req
    '';
  in {
    environment.etc."caddy/tls/server.crt".source = "${certs}/server.crt";
    environment.etc."caddy/tls/server.key".source = "${certs}/server.key";
    environment.etc."caddy/tls/ca.crt".source = "${certs}/ca.crt";
    security.pki.certificates = [ (builtins.readFile "${certs}/ca.crt") ];
  });
}


