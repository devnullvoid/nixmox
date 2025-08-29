terraform {
  required_version = ">= 1.6.0"
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2024.10.0"
    }
  }
}

provider "authentik" {
  # These can be provided via environment variables as well:
  # AUTHENTIK_URL, AUTHENTIK_TOKEN, AUTHENTIK_INSECURE (true/false)
  url      = var.authentik_url
  token    = var.authentik_token
  insecure = var.authentik_insecure
}

data "authentik_flow" "default_authentication" {
  slug = "default-authentication-flow"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-invalidation-flow"
}

# Provider Authorization flow used by OAuth2 providers (implicit consent)
data "authentik_flow" "provider_authorize_implicit" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_property_mapping_provider_scope" "scope_openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "scope_email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "scope_profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_property_mapping_provider_scope" "scope_offline" {
  managed = "goauthentik.io/providers/oauth2/scope-offline_access"
}

resource "authentik_provider_oauth2" "vaultwarden" {
  name               = "Vaultwarden OIDC"
  client_id          = var.vw_client_id
  client_secret      = var.vw_client_secret
  authorization_flow = data.authentik_flow.provider_authorize_implicit.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "confidential"


  # Token lifetimes to avoid frontend 5min collision
  access_token_validity  = "minutes=60"
  refresh_token_validity = "days=30"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = var.vw_redirect_uri
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.scope_openid.id,
    data.authentik_property_mapping_provider_scope.scope_email.id,
    data.authentik_property_mapping_provider_scope.scope_profile.id,
    data.authentik_property_mapping_provider_scope.scope_offline.id,
  ]

  lifecycle {
    ignore_changes = [
      client_id,
      client_secret,
    ]
  }
}

resource "authentik_application" "vaultwarden" {
  name              = "Vaultwarden"
  slug              = "vaultwarden"
  protocol_provider = authentik_provider_oauth2.vaultwarden.id
  meta_launch_url   = var.vw_launch_url
  open_in_new_tab   = true
}

output "provider_id" {
  value = authentik_provider_oauth2.vaultwarden.id
}

output "application_id" {
  value = authentik_application.vaultwarden.id
}

