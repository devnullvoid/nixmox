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

# LDAP provider
resource "authentik_provider_ldap" "ldap" {
  name       = var.ldap_provider_name
  base_dn    = var.ldap_base_dn
  bind_flow  = data.authentik_flow.default_authentication.id
  unbind_flow = data.authentik_flow.default_invalidation.id

  bind_mode   = var.ldap_bind_mode
  search_mode = var.ldap_search_mode
  mfa_support = var.ldap_mfa_support

  uid_start_number = var.ldap_uid_start_number
  gid_start_number = var.ldap_gid_start_number
}

# Application that exposes the LDAP directory
resource "authentik_application" "ldap" {
  name              = var.ldap_app_name
  slug              = var.ldap_app_slug
  protocol_provider = authentik_provider_ldap.ldap.id
}

# LDAP outpost
resource "authentik_outpost" "ldap" {
  name = var.ldap_outpost_name
  type = "ldap"

  protocol_providers = [
    authentik_provider_ldap.ldap.id,
  ]

  config = jsonencode({
    authentik_host = var.authentik_url
    authentik_host_insecure = var.authentik_insecure
    log_level = "info"
    docker_map_ports = true
    kubernetes_replicas = 1
    kubernetes_namespace = "authentik"
    kubernetes_service_type = "ClusterIP"
    kubernetes_disabled_components = []
    kubernetes_image_pull_secrets = []
    kubernetes_ingress_annotations = {}
    kubernetes_ingress_secret_name = "authentik-outpost-tls"
    object_naming_template = "ak-outpost-%(name)s"
    refresh_interval = "minutes=5"

  })
}

output "provider_id" {
  value = authentik_provider_ldap.ldap.id
}

output "application_id" {
  value = authentik_application.ldap.id
}

output "outpost_id" {
  value = authentik_outpost.ldap.id
}


