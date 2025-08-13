# Authentik Guacamole OIDC (Terraform)

This module creates an Authentik OAuth2 (OIDC) Provider and Application for Apache Guacamole.

Inputs:
- `authentik_url` (e.g., `https://auth.nixmox.lan`)
- `authentik_token` (automation API token)
- `authentik_insecure` (bool, default `true` for self-signed)
- `guac_client_id`, `guac_client_secret`
- `guac_redirect_uri` (e.g., `https://guac.nixmox.lan/`)
- `guac_app_name`, `guac_app_slug`, `guac_app_group`, `guac_launch_url`

Outputs:
- `guacamole_provider_id`
- `guacamole_application_id`

Example usage:

```hcl
module "authentik_guacamole" {
  source = "./terraform/authentik/guacamole"

  authentik_url      = var.authentik_url
  authentik_token    = var.authentik_token
  authentik_insecure = true

  guac_client_id     = var.guac_client_id
  guac_client_secret = var.guac_client_secret
  guac_redirect_uri  = "https://guac.nixmox.lan/"

  guac_app_name   = "Guacamole"
  guac_app_slug   = "guacamole"
  guac_app_group  = "Remote Access"
  guac_launch_url = "https://guac.nixmox.lan/"
}
```

Notes:
- Ensure Guacamole OIDC config matches the Provider slug and endpoints.
- Add `guac.nixmox.lan` to local TLS issuance and Caddy.
- For first-run, the Guacamole DB schema is bootstrapped via a systemd oneshot.


