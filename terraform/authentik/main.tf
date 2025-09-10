terraform {
  required_version = ">= 1.6.0"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
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

provider "sops" {}

# Variables
variable "secrets_file" {
  description = "Path to SOPS encrypted secrets file"
  type        = string
  default     = ""
}

# SOPS data source
data "sops_file" "secrets" {
  count = var.secrets_file != "" ? 1 : 0
  source_file = var.secrets_file
}

# External data source for manifest
data "external" "manifest" {
  program = ["nix", "eval", "-f", "${path.module}/../terraform-manifest.nix", "--json"]
}

# Local values from manifest
locals {
  manifest = data.external.manifest.result
  
  # Parse JSON strings back to objects
  oidc_apps = jsondecode(local.manifest.oidc_apps)
  proxy_apps = jsondecode(local.manifest.proxy_apps)
  ldap_app = jsondecode(local.manifest.ldap_app)
  radius_app = jsondecode(local.manifest.radius_app)
  outpost_config = jsondecode(local.manifest.outpost_config)
  
  # Try to read from SOPS file if provided
  secrets_data = var.secrets_file != "" ? data.sops_file.secrets[0].data : {}
  
  # Get Authentik URL from manifest
  authentik_url = local.manifest.authentik_url
}

# Authentik provider configuration
provider "authentik" {
  url      = local.authentik_url
  token    = try(local.secrets_data.authentik_bootstrap_token, "")
  insecure = true
}

# Authentik Manifest Module
module "authentik_manifest" {
  source = "../modules/authentik-manifest"

  authentik_url      = local.authentik_url
  authentik_token    = try(local.secrets_data.authentik_bootstrap_token, "")
  authentik_insecure = true

  oidc_apps      = local.manifest.oidc_apps
  proxy_apps     = local.manifest.proxy_apps
  ldap_app       = local.manifest.ldap_app
  radius_app     = local.manifest.radius_app
  outpost_config = local.manifest.outpost_config

  # Pass secrets data for OIDC client secrets
  secrets_data = local.secrets_data
}

# Outputs
output "authentik_ldap_outpost_id" {
  description = "LDAP outpost ID for getting view key"
  value       = module.authentik_manifest.ldap_outpost_id
}

output "authentik_radius_outpost_id" {
  description = "RADIUS outpost ID for getting view key"
  value       = module.authentik_manifest.radius_outpost_id
}

output "authentik_oidc_apps" {
  description = "Generated OIDC applications from manifest"
  value       = module.authentik_manifest.oidc_apps
  sensitive   = true
}

output "authentik_ready" {
  description = "Whether Authentik outposts and OIDC apps are deployed"
  value       = true
}

output "manifest_summary" {
  description = "Summary of manifest data"
  value = {
    total_services = parseint(local.manifest.total_services, 10)
    network_domain = local.manifest.network_domain
    network_cidr = local.manifest.network_cidr
  }
}
