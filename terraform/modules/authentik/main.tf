# Basic Authentik module for outpost configuration
# This is a placeholder module that can be expanded later

variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
}

variable "authentik_bootstrap_token" {
  description = "Authentik bootstrap token for API access"
  type        = string
}

variable "ldap_outpost_config" {
  description = "LDAP outpost configuration"
  type = object({
    name = string
    search_base_dn = string
    bind_dn = string
    bind_password = string
    search_group = string
    additional_user_dn = string
    additional_group_dn = string
    user_object_filter = string
    group_object_filter = string
    group_membership_field = string
    object_uniqueness_field = string
  })
}

variable "radius_outpost_config" {
  description = "RADIUS outpost configuration"
  type = object({
    name = string
    shared_secret = string
    client_networks = list(string)
  })
}

# Placeholder outputs for now
output "ldap_outpost_id" {
  description = "LDAP outpost ID"
  value       = "ldap-outpost-${random_id.ldap.hex}"
}

output "radius_outpost_id" {
  description = "RADIUS outpost ID"
  value       = "radius-outpost-${random_id.radius.hex}"
}

# Generate random IDs for the outposts
resource "random_id" "ldap" {
  byte_length = 8
}

resource "random_id" "radius" {
  byte_length = 8
}
