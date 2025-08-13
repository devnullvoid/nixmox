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
  url      = var.authentik_url
  token    = var.authentik_token
  insecure = var.authentik_insecure
}

# Flows
data "authentik_flow" "default_authentication" {
  slug = "default-authentication-flow"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-invalidation-flow"
}

data "authentik_flow" "provider_authorize_implicit" {
  slug = "default-provider-authorization-implicit-consent"
}

# Scopes
data "authentik_property_mapping_provider_scope" "scope_openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "scope_email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "scope_profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

resource "authentik_provider_oauth2" "guacamole" {
  name               = var.guac_provider_name
  client_id          = var.guac_client_id
  authorization_flow = data.authentik_flow.provider_authorize_implicit.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "public"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = var.guac_redirect_uri
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.scope_openid.id,
    data.authentik_property_mapping_provider_scope.scope_email.id,
    data.authentik_property_mapping_provider_scope.scope_profile.id,
  ]
}

resource "authentik_application" "guacamole" {
  name              = var.guac_app_name
  slug              = var.guac_app_slug
  protocol_provider = authentik_provider_oauth2.guacamole.id
  group             = var.guac_app_group
  # Meta launch URL only (newer provider schema)
  meta_launch_url   = var.guac_launch_url
  meta_icon         = "mdi:remote-desktop"
  meta_publisher    = "NixMox"
  open_in_new_tab   = false
}


