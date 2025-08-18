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

# RADIUS provider
resource "authentik_provider_radius" "radius" {
  name               = var.radius_provider_name
  authorization_flow = data.authentik_flow.default_authentication.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  shared_secret      = var.radius_shared_secret
  client_networks    = var.radius_client_networks
  mfa_support        = var.radius_mfa_support
}

# Application for RADIUS access
resource "authentik_application" "radius" {
  name              = var.radius_app_name
  slug              = var.radius_app_slug
  protocol_provider = authentik_provider_radius.radius.id
}

# RADIUS outpost
resource "authentik_outpost" "radius" {
  name = var.radius_outpost_name
  type = "radius"

  protocol_providers = [
    authentik_provider_radius.radius.id,
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
  value = authentik_provider_radius.radius.id
}

output "application_id" {
  value = authentik_application.radius.id
}

output "outpost_id" {
  value = authentik_outpost.radius.id
}


