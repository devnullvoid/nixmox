terraform {
  required_version = ">= 1.6.0"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 2.9"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
    external = {
      source = "hashicorp/external"
      version = "~> 2.0"
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
provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = var.pm_tls_insecure
}

provider "authentik" {
  url      = "http://192.168.99.12:9000"  # Authentik IP from manifest
  token    = try(local.secrets_data.authentik_bootstrap_token, "")
  insecure = true
}

# Variables
variable "pm_api_url" {
  description = "Proxmox API URL (required if no secrets_file provided)"
  type        = string
  default     = ""
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID (required if no secrets_file provided)"
  type        = string
  default     = ""
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret (required if no secrets_file provided)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pm_tls_insecure" {
  description = "Allow insecure TLS connections to Proxmox"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment to deploy (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "deployment_phase" {
  description = "Deployment phase (1=infrastructure, 2=core, 3=applications)"
  type        = number
  default     = 1
  validation {
    condition     = var.deployment_phase >= 1 && var.deployment_phase <= 3
    error_message = "Deployment phase must be between 1 and 3."
  }
}

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
  program = ["nix", "eval", "-f", "${path.module}/terraform-manifest.nix", "--json"]
}

# Local values from manifest
locals {
  manifest = data.external.manifest.result
  
  # Parse JSON strings back to objects
  phase1_containers = jsondecode(local.manifest.phase1_containers)
  phase2_containers = jsondecode(local.manifest.phase2_containers)
  phase3_containers = jsondecode(local.manifest.phase3_containers)
  network_config = jsondecode(local.manifest.network_config)
  dns_records = jsondecode(local.manifest.dns_records)
  
  # Environment-specific configurations
  env_configs = {
    dev = {
      resource_multiplier = 1.0
      enable_debug       = true
      backup_enabled     = false
      monitoring_level   = "basic"
    }
    staging = {
      resource_multiplier = 1.0
      enable_debug       = false
      backup_enabled     = true
      monitoring_level   = "standard"
    }
    prod = {
      resource_multiplier = 1.5
      enable_debug       = false
      backup_enabled     = true
      monitoring_level   = "full"
    }
  }

  current_env = local.env_configs[var.environment]
  
  # Try to read from SOPS file if provided, otherwise use variables
  secrets_data = var.secrets_file != "" ? data.sops_file.secrets[0].data : {}
  
  # Validation that either secrets_file or individual variables are provided
  credentials_provided = (
    var.secrets_file != "" || 
    (var.pm_api_url != "" && var.pm_api_token_id != "" && var.pm_api_token_secret != "")
  )
  
  # Get containers to deploy based on phase
  containers_to_deploy = merge(
    var.deployment_phase >= 1 ? local.phase1_containers : {},
    var.deployment_phase >= 2 ? local.phase2_containers : {},
    var.deployment_phase >= 3 ? local.phase3_containers : {}
  )
}

# Proxmox LXC module
module "lxc" {
  source = "./modules/proxmox-lxc"

  pm_api_url          = try(local.secrets_data.pm_api_url, var.pm_api_url)
  pm_api_token_id     = try(local.secrets_data.pm_api_token_id, var.pm_api_token_id)
  pm_api_token_secret = try(local.secrets_data.pm_api_token_secret, var.pm_api_token_secret)
  pm_tls_insecure     = try(local.secrets_data.pm_tls_insecure, var.pm_tls_insecure)

  node    = try(local.secrets_data.node, "kuiper-belt")
  pool    = try(local.secrets_data.pool, "local-lvm")
  bridge  = try(local.secrets_data.bridge, "vmbr0")
  cidr    = try(local.secrets_data.cidr, "192.168.99.0/24")
  storage = try(local.secrets_data.storage, "callisto-ssd")

  ssh_public_keys        = try(local.secrets_data.ssh_public_keys, "")
  provision_with_rebuild = try(local.secrets_data.provision_with_rebuild, false)
  flake_root             = try(local.secrets_data.flake_root, "")
  hydra_template         = try(local.secrets_data.hydra_template, "")
  nixos_version          = try(local.secrets_data.nixos_version, "25.05")

  pve_host            = try(local.secrets_data.pve_host, "")
  pve_user            = try(local.secrets_data.pve_user, "root")
  pve_ssh_private_key = try(local.secrets_data.pve_ssh_private_key, "")
  pve_ssh_port        = try(local.secrets_data.pve_ssh_port, 22)

  containers = local.containers_to_deploy
}

# Authentik Manifest Module (Phase 2: Core Authentication)
module "authentik_manifest" {
  count = var.deployment_phase >= 2 ? 1 : 0
  source = "./modules/authentik-manifest"

  authentik_url      = local.manifest.authentik_url
  authentik_token    = try(local.secrets_data.authentik_bootstrap_token, "")
  authentik_insecure = true

  oidc_apps      = local.manifest.oidc_apps
  outpost_config = local.manifest.outpost_config
}

# Outputs
output "deployment_phase" {
  description = "Current deployment phase"
  value       = var.deployment_phase
}

output "deployed_containers" {
  description = "List of deployed containers"
  value       = keys(local.containers_to_deploy)
}

output "next_phase_containers" {
  description = "Containers that would be deployed in the next phase"
  value = var.deployment_phase < 3 ? (
    var.deployment_phase == 1 ? keys(local.phase2_containers) :
    var.deployment_phase == 2 ? keys(local.phase3_containers) : []
  ) : []
}

output "network_config" {
  description = "Network configuration from manifest"
  value       = local.network_config
}

output "dns_records" {
  description = "DNS records from manifest"
  value       = local.dns_records
}

output "environment" {
  description = "Current deployment environment"
  value       = var.environment
}

output "resource_multiplier" {
  description = "Resource multiplier for current environment"
  value       = local.current_env.resource_multiplier
}

output "manifest_summary" {
  description = "Summary of manifest data"
  value = {
    total_services = parseint(local.manifest.total_services, 10)
    phase1_services = parseint(local.manifest.phase1_count, 10)
    phase2_services = parseint(local.manifest.phase2_count, 10)
    phase3_services = parseint(local.manifest.phase3_count, 10)
    network_domain = local.manifest.network_domain
    network_cidr = local.manifest.network_cidr
  }
}

# Authentik outputs
output "authentik_ldap_outpost_id" {
  description = "LDAP outpost ID for getting view key"
  value       = var.deployment_phase >= 2 ? module.authentik_manifest[0].ldap_outpost_id : null
}

output "authentik_radius_outpost_id" {
  description = "RADIUS outpost ID for getting view key"
  value       = var.deployment_phase >= 2 ? module.authentik_manifest[0].radius_outpost_id : null
}

output "authentik_oidc_apps" {
  description = "Generated OIDC applications from manifest"
  value       = var.deployment_phase >= 2 ? module.authentik_manifest[0].oidc_apps : null
  sensitive   = true
}

output "authentik_ready" {
  description = "Whether Authentik outposts and OIDC apps are deployed"
  value       = var.deployment_phase >= 2
}
