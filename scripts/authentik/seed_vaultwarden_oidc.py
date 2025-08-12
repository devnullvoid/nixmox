from authentik.core.models import Application
from authentik.flows.models import Flow
from authentik.providers.oauth2.models import OAuth2Provider


def ensure_vaultwarden():
    flow = Flow.objects.get(slug="default-authentication-flow")
    app, _ = Application.objects.get_or_create(
        slug="vaultwarden",
        defaults={"name": "Vaultwarden"},
    )
    prov, _ = OAuth2Provider.objects.get_or_create(
        name="Vaultwarden OIDC",
        defaults={
            "authorization_flow": flow,
            "client_type": "confidential",
            "redirect_uris": [
                "http://vault.nixmox.lan/oidc/callback",
            ],
            "signing_key": None,
            "allowed_scopes": ["openid", "email", "profile"],
        },
    )
    app.provider = prov
    app.save()
    return app, prov


if __name__ == "__main__":
    app, prov = ensure_vaultwarden()
    print({
        "app": app.slug,
        "provider": prov.slug,
        "client_id": prov.client_id,
        "client_secret": prov.client_secret,
    })


