## Guacamole + Authentik (OIDC) behind Caddy

Summary of the working prototype for `guac.nixmox.lan`.

- Public URL: `https://guac.nixmox.lan/guacamole/`
- Backend Tomcat: `http://guacamole.nixmox.lan:8280/guacamole/`
- IdP: Authentik at `https://auth.nixmox.lan`

### Key NixOS modules/paths
- `nixos/modules/guacamole/default.nix`: Guacamole client/server + OIDC settings
- `nixos/modules/caddy/services.nix`: Caddy reverse proxy service block for Guacamole

### Caddy config essentials
- Serve `guac.nixmox.lan` with our wildcard cert
- Reverse-proxy all requests to `guacamole.nixmox.lan:8280`
- Forward proxy headers to avoid OIDC loops:
  - `X-Forwarded-For`
  - `X-Forwarded-Proto`
  - `X-Forwarded-Host`

Resulting service extraConfig for Guacamole:
```
# Add proper headers for reverse proxy to prevent redirect loops
header_up X-Forwarded-For {remote_host}
header_up X-Forwarded-Proto {scheme}
header_up X-Forwarded-Host {host}

# Simple reverse proxy - let Guacamole handle all paths including OIDC redirects
reverse_proxy guacamole.nixmox.lan:8280
```

Note: Guacamole is actually hosted at `/guacamole/` on Tomcat; browsing `https://guac.nixmox.lan/guacamole/` is correct. Root `/` may 404 and is expected.

### Guacamole OIDC settings (in-module)
- `openid-authorization-endpoint = https://auth.nixmox.lan/application/o/authorize/`
- `openid-jwks-endpoint = https://auth.nixmox.lan/application/o/guacamole/jwks/`
- `openid-issuer = https://auth.nixmox.lan/application/o/guacamole/`
- `openid-client-id = guacamole-client`
- `openid-redirect-uri = https://guac.nixmox.lan/guacamole/` (critical)
- `openid-username-claim-type = preferred_username`
- `openid-scope = openid email profile`
- Additional stabilizers used:
  - `openid-allowed-redirect-uris = https://guac.nixmox.lan/guacamole/`
  - `openid-validate-token = true`
  - `openid-max-token-length = 8192`

### Authentik provider
- App/provider pair dedicated to Guacamole
- Redirect URI must be `https://guac.nixmox.lan/guacamole/`
- During troubleshooting, a permissive regex `https://guac\.nixmox\.lan/.*` also worked. After headers/Guac config fixes, strict redirect URI suffices.

### Java truststore for internal CA
- We import the internal CA into a Tomcat/Java truststore so Guacamole trusts Authentik TLS:
```
keytool -importcert -trustcacerts -alias nixmox-internal-ca \
  -file /var/lib/shared-certs/internal-ca.crt \
  -keystore /var/lib/guacamole/java-cacerts \
  -storepass changeit -noprompt
```
- Tomcat is launched with:
  - `-Djavax.net.ssl.trustStore=/var/lib/guacamole/java-cacerts`
  - `-Djavax.net.ssl.trustStorePassword=changeit`

### Common failure modes we hit
- Blank page via proxy: backend not running or Caddy reverse proxy mis-config
- Caddy reload errors: invalid directives (e.g., `buffer off`) or admin API transient failures; retries succeed
- 404 at root `/`: expected; use `/guacamole/`
- OIDC redirect loop: fixed by forwarding `X-Forwarded-*` headers and ensuring redirect URI is `/guacamole/`; optional `openid-allowed-redirect-uris`

### Deployment & health
- `deploy-smart.sh` includes retries (Sophos NGFW flakiness) and correct guacamole health check: `guacamole-server.service` and `tomcat.service`
- External PostgreSQL reachable; schema bootstrapped by `guacamole-pgsql-schema-import.service`

### Next steps
- Add SOPS for DB password
- Finalize OIDC group/role mapping
- Document pattern for service manifests and orchestrated dependency deploys
