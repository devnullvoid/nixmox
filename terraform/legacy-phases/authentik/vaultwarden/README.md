# Vaultwarden OIDC in Authentik (Terraform)

Usage:

- Set provider env vars (recommended):

```bash
export AUTHENTIK_URL="https://auth.nixmox.lan"
export AUTHENTIK_TOKEN="<api_token>"
```

- Or pass as variables. Then:

```bash
cd terraform/authentik/vaultwarden
terraform init
terraform apply \
  -var authentik_url="$AUTHENTIK_URL" \
  -var authentik_token="$AUTHENTIK_TOKEN" \
  -var vw_client_id="<OIDC_CLIENT_ID>" \
  -var vw_client_secret="<OIDC_CLIENT_SECRET>" \
  -var vw_redirect_uri="https://vault.nixmox.lan/oidc/callback"
```

Creates:
- OAuth2 provider and linked application for Vaultwarden.

After apply, test login at `https://vault.nixmox.lan`.
