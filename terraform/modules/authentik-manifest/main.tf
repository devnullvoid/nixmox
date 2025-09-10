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

variable "proxy_apps" {
  description = "Proxy application configurations from manifest"
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



# No deployment_phase needed - this module deploys all authentik resources



variable "secrets_data" {
  description = "Secrets data from SOPS file"
  type        = map(any)
  default     = {}
}

# Local values
locals {
  oidc_apps_data = jsondecode(var.oidc_apps)
  proxy_apps_data = jsondecode(var.proxy_apps)
  ldap_app_data = jsondecode(var.ldap_app)
  radius_app_data = jsondecode(var.radius_app)
  outpost_config_data = jsondecode(var.outpost_config)

  # OIDC apps (all apps, filtered by deployment phase in resources)
  oidc_apps = local.oidc_apps_data
  
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

# Custom scope mapping for Nextcloud
resource "authentik_property_mapping_provider_scope" "nextcloud_profile" {
  name       = "Nextcloud Profile"
  scope_name = "nextcloud"
  expression = <<-EOT
# Extract all groups the user is a member of
groups = [group.name for group in user.ak_groups.all()]

# In Nextcloud, administrators must be members of a fixed group called "admin".
# If a user is an admin in authentik, ensure that "admin" is appended to their group list.
if user.is_superuser and "admin" not in groups:
    groups.append("admin")

return {
    "name": request.user.name,
    "groups": groups,
    # Set a quota by using the "nextcloud_quota" property in the user's attributes
    "quota": user.group_attributes().get("nextcloud_quota", None),
    # To connect an existing Nextcloud user, set "nextcloud_user_id" to the Nextcloud username.
    "user_id": user.attributes.get("nextcloud_user_id", str(user.uuid)),
}
EOT
}

# LDAP provider (for exposing Authentik users via LDAP)
resource "authentik_provider_ldap" "ldap" {
  name       = "LDAP Provider"

  lifecycle {
    prevent_destroy = true
  }
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

  lifecycle {
    prevent_destroy = true
  }

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

  lifecycle {
    prevent_destroy = true
  }
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

  lifecycle {
    prevent_destroy = true
  }

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
  for_each = local.oidc_apps

  name               = "${each.value.name} OIDC"

  client_id          = each.value.oidc_client_id
  client_secret      = local.oidc_client_secrets[each.key]
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

  property_mappings = concat(
    [
      for scope in local.default_scopes : data.authentik_property_mapping_provider_scope.scopes[scope].id
    ],
    # Add Nextcloud-specific scope mapping only for Nextcloud service
    each.key == "nextcloud" ? [authentik_property_mapping_provider_scope.nextcloud_profile.id] : []
  )

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      # client_id,
      # client_secret,
      signing_key,
    ]
  }
}

# Extract OIDC client secrets from secrets data based on client type
locals {
  confidential_clients = [
    for svc_name, svc_config in local.oidc_apps :
    svc_name if svc_config.oidc_client_type == "confidential"
  ]

  # Extract oidc_client_secret from secrets file for each service
  # The secrets_data structure is flat: { "nextcloud.oidc_client_secret" = "...", "vaultwarden.oidc_client_secret" = "..." }
  oidc_client_secrets_from_file = {
    for svc_name in local.confidential_clients :
    svc_name => try(var.secrets_data["${svc_name}.oidc_client_secret"], null)
    if can(var.secrets_data["${svc_name}.oidc_client_secret"])
  }

  # Confidential clients that need random passwords (no secret in file)
  clients_needing_random = {
    for svc_name, svc_config in local.oidc_apps :
    svc_name => svc_config
    if svc_config.oidc_client_type == "confidential" &&
       !can(lookup(local.oidc_client_secrets_from_file, svc_name, null))
  }

  # For confidential clients: use from file if exists, otherwise use random
  # For public clients: always null
  oidc_client_secrets = {
    for svc_name, svc_config in local.oidc_apps :
    svc_name => (
      svc_config.oidc_client_type == "public" ? null :
      lookup(local.oidc_client_secrets_from_file, svc_name,
             try(random_password.oidc_client_secrets[svc_name].result, null))
    )
  }
}

# Generate random client secrets for confidential clients without secrets in file
resource "random_password" "oidc_client_secrets" {
  for_each = local.clients_needing_random

  length  = 32
  special = true
}

# Generate applications for each OIDC service
resource "authentik_application" "oidc_apps" {
  for_each = local.oidc_apps

  name              = each.value.name
  slug              = each.value.name
  protocol_provider = authentik_provider_oauth2.oidc_apps[each.key].id

  lifecycle {
    prevent_destroy = true
  }
  meta_launch_url   = each.value.launch_url
  open_in_new_tab   = each.value.open_in_new_tab
}

# Generate Proxy providers for each forward auth service
resource "authentik_provider_proxy" "proxy_apps" {
  for_each = local.proxy_apps_data

  name               = "${each.value.name} Proxy"
  external_host      = each.value.external_host
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.provider_authorize_implicit.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id

  lifecycle {
    prevent_destroy = true
  }
}

# Generate applications for each Proxy service
resource "authentik_application" "proxy_apps" {
  for_each = local.proxy_apps_data

  name              = each.value.name
  slug              = each.value.name
  protocol_provider = authentik_provider_proxy.proxy_apps[each.key].id

  lifecycle {
    prevent_destroy = true
  }
  meta_launch_url   = each.value.launch_url
  open_in_new_tab   = each.value.open_in_new_tab
}

# Data source to dynamically discover embedded outpost ID
data "external" "embedded_outpost_id" {
  program = ["bash", "../../scripts/get-embedded-outpost-id.sh"]
}

# Embedded Proxy outpost (manage existing one)
resource "authentik_outpost" "embedded" {
  name = "authentik Embedded Outpost"
  type = "proxy"

  protocol_providers = [
    for provider in authentik_provider_proxy.proxy_apps : provider.id
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes = [config]
  }
}



# Generate LDAP application
resource "authentik_application" "ldap_app" {
  name              = local.ldap_app_data.name
  slug              = local.ldap_app_data.slug
  protocol_provider = authentik_provider_ldap.ldap.id

  lifecycle {
    prevent_destroy = true
  }
  meta_description  = local.ldap_app_data.meta_description
  meta_launch_url   = local.ldap_app_data.meta_launch_url
  open_in_new_tab   = local.ldap_app_data.open_in_new_tab
}

# Generate RADIUS application
resource "authentik_application" "radius_app" {
  name              = local.radius_app_data.name
  slug              = local.radius_app_data.slug
  protocol_provider = authentik_provider_radius.radius.id

  lifecycle {
    prevent_destroy = true
  }
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
    for name, app in authentik_application.oidc_apps :
    name => {
      id = app.id
      name = app.name
      slug = app.slug
      protocol_provider = app.protocol_provider
    }
  }
}

output "confidential_clients" {
  description = "List of confidential clients that need secrets"
  value = local.confidential_clients
}

