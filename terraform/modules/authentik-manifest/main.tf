terraform {
  required_version = ">= 1.6.0"
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2024.10.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Variables
variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
}

variable "authentik_token" {
  description = "Authentik API token"
  type        = string
  sensitive   = true
}

variable "authentik_insecure" {
  description = "Allow insecure connections to Authentik"
  type        = bool
  default     = false
}

variable "oidc_apps" {
  description = "OIDC application configurations from manifest"
  type        = string
}

variable "ldap_app" {
  description = "LDAP application configuration from manifest"
  type        = string
}

variable "radius_app" {
  description = "RADIUS application configuration from manifest"
  type        = string
}

variable "outpost_config" {
  description = "Outpost configuration from manifest"
  type        = string
}

variable "incremental_mode" {
  description = "Enable incremental deployment mode"
  type        = bool
  default     = false
}

variable "oidc_apps_to_create" {
  description = "List of OIDC apps to create (for incremental mode)"
  type        = list(string)
  default     = []
}

# Local values
locals {
  oidc_apps_data = jsondecode(var.oidc_apps)
  ldap_app_data = jsondecode(var.ldap_app)
  radius_app_data = jsondecode(var.radius_app)
  outpost_config_data = jsondecode(var.outpost_config)

  # Filter OIDC apps for incremental deployment
  filtered_oidc_apps = var.incremental_mode ? {
    for app_name, app_config in local.oidc_apps_data :
    app_name => app_config
    if contains(var.oidc_apps_to_create, app_name)
  } : local.oidc_apps_data
  
  # Default flows
  default_flows = {
    authentication = "default-authentication-flow"
    invalidation = "default-invalidation-flow"
    provider_authorize = "default-provider-authorization-implicit-consent"
  }
  
  # Default scopes
  default_scopes = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email", 
    "goauthentik.io/providers/oauth2/scope-profile",
    "goauthentik.io/providers/oauth2/scope-offline_access"
  ]
}

# Data sources for flows
data "authentik_flow" "default_authentication" {
  slug = local.default_flows.authentication
}

data "authentik_flow" "default_invalidation" {
  slug = local.default_flows.invalidation
}

data "authentik_flow" "provider_authorize_implicit" {
  slug = local.default_flows.provider_authorize
}

# Data sources for scope mappings
data "authentik_property_mapping_provider_scope" "scopes" {
  for_each = toset(local.default_scopes)
  managed  = each.value
}

# LDAP provider (for exposing Authentik users via LDAP)
resource "authentik_provider_ldap" "ldap" {
  name       = "LDAP Provider"
  base_dn    = local.outpost_config_data.ldap.base_dn
  bind_flow  = data.authentik_flow.default_authentication.id
  unbind_flow = data.authentik_flow.default_invalidation.id

  bind_mode   = "direct"
  search_mode = "direct"
  mfa_support = false

  uid_start_number = 1000
  gid_start_number = 1000
}

# LDAP outpost (exposes Authentik users via LDAP)
resource "authentik_outpost" "ldap" {
  name = "LDAP Outpost"
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

# RADIUS provider (for exposing Authentik users via RADIUS)
resource "authentik_provider_radius" "radius" {
  name               = "RADIUS Provider"
  authorization_flow = data.authentik_flow.default_authentication.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  shared_secret      = local.outpost_config_data.radius.shared_secret
  client_networks    = local.outpost_config_data.radius.client_networks
  mfa_support        = false
}

# RADIUS outpost (exposes Authentik users via RADIUS)
resource "authentik_outpost" "radius" {
  name = "RADIUS Outpost"
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

# Generate OIDC providers for each service in the manifest
resource "authentik_provider_oauth2" "oidc_apps" {
  for_each = local.filtered_oidc_apps
  
  name               = "${each.value.name} OIDC"
  client_id          = each.value.oidc_client_id
  client_secret      = each.value.oidc_client_type == "confidential" ? random_password.oidc_secrets[each.key].result : null
  authorization_flow = data.authentik_flow.provider_authorize_implicit.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = each.value.oidc_client_type

  # Token lifetimes to avoid frontend 5min collision
  access_token_validity  = "minutes=60"
  refresh_token_validity = "days=30"

  allowed_redirect_uris = [
    for uri in each.value.redirect_uris : {
      matching_mode = "strict"
      url           = uri
    }
  ]

  property_mappings = [
    for scope in local.default_scopes : data.authentik_property_mapping_provider_scope.scopes[scope].id
  ]

  lifecycle {
    ignore_changes = [
      client_id,
      client_secret,
    ]
  }
}

# Generate random secrets for confidential OIDC clients only
resource "random_password" "oidc_secrets" {
  for_each = {
    for name, config in local.filtered_oidc_apps : name => config
    if config.oidc_client_type == "confidential"
  }
  
  length  = 32
  special = true
}

# Generate applications for each OIDC service
resource "authentik_application" "oidc_apps" {
  for_each = local.filtered_oidc_apps

  name              = each.value.name
  slug              = each.value.name
  protocol_provider = authentik_provider_oauth2.oidc_apps[each.key].id
  meta_launch_url   = each.value.launch_url
  open_in_new_tab   = each.value.open_in_new_tab
}

# Generate LDAP application
resource "authentik_application" "ldap_app" {
  name              = local.ldap_app_data.name
  slug              = local.ldap_app_data.slug
  protocol_provider = authentik_provider_ldap.ldap.id
  meta_description  = local.ldap_app_data.meta_description
  meta_launch_url   = local.ldap_app_data.meta_launch_url
  open_in_new_tab   = local.ldap_app_data.open_in_new_tab
}

# Generate RADIUS application
resource "authentik_application" "radius_app" {
  name              = local.radius_app_data.name
  slug              = local.radius_app_data.slug
  protocol_provider = authentik_provider_radius.radius.id
  meta_description  = local.radius_app_data.meta_description
  meta_launch_url   = local.radius_app_data.meta_launch_url
  open_in_new_tab   = local.radius_app_data.open_in_new_tab
}

# Outputs
output "ldap_outpost_id" {
  description = "LDAP outpost ID"
  value       = authentik_outpost.ldap.id
}

output "radius_outpost_id" {
  description = "RADIUS outpost ID"
  value       = authentik_outpost.radius.id
}

output "oidc_apps" {
  description = "Generated OIDC applications"
  value = {
    for name, app in authentik_application.oidc_apps : name => {
      id = app.id
      slug = app.slug
      provider_id = authentik_provider_oauth2.oidc_apps[name].id
      client_id = authentik_provider_oauth2.oidc_apps[name].client_id
      client_secret = authentik_provider_oauth2.oidc_apps[name].client_secret
    }
  }
  sensitive = true
}

