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
  }
}

provider "sops" {}

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
  all_containers = jsondecode(local.manifest.all_containers)
  network_config = jsondecode(local.manifest.network_config)
  
  # Try to read from SOPS file if provided, otherwise use variables
  secrets_data = var.secrets_file != "" ? data.sops_file.secrets[0].data : {}
  
  # Validation that either secrets_file or individual variables are provided
  credentials_provided = (
    var.secrets_file != "" || 
    (var.pm_api_url != "" && var.pm_api_token_id != "" && var.pm_api_token_secret != "")
  )
}

# Proxmox provider configuration
provider "proxmox" {
  pm_api_url          = try(local.secrets_data.pm_api_url, var.pm_api_url)
  pm_api_token_id     = try(local.secrets_data.pm_api_token_id, var.pm_api_token_id)
  pm_api_token_secret = try(local.secrets_data.pm_api_token_secret, var.pm_api_token_secret)
  pm_tls_insecure     = try(local.secrets_data.pm_tls_insecure, var.pm_tls_insecure)
}

# Proxmox LXC module
module "lxc" {
  source = "../modules/proxmox-lxc"

  pm_api_url          = try(local.secrets_data.pm_api_url, var.pm_api_url)
  pm_api_token_id     = try(local.secrets_data.pm_api_token_id, var.pm_api_token_id)
  pm_api_token_secret = try(local.secrets_data.pm_api_token_secret, var.pm_api_token_secret)
  pm_tls_insecure     = try(local.secrets_data.pm_tls_insecure, var.pm_tls_insecure)

  node    = try(local.secrets_data.node, "uranus")
  pool    = try(local.secrets_data.pool, "nixmox")
  bridge  = try(local.secrets_data.bridge, "vmbr0")
  cidr    = try(local.secrets_data.cidr, "192.168.99.0/24")
  storage = try(local.secrets_data.storage, "callisto-ssd")

  ssh_public_keys        = try(local.secrets_data.ssh_public_keys, "")
  provision_with_rebuild = try(local.secrets_data.provision_with_rebuild, false)
  provision_with_bootstrap = false  # Disable bootstrap for existing containers
  flake_root             = try(local.secrets_data.flake_root, "")
  hydra_template         = try(local.secrets_data.hydra_template, "")
  nixos_version          = try(local.secrets_data.nixos_version, "25.05")

  pve_host            = try(local.secrets_data.pve_host, "")
  pve_user            = try(local.secrets_data.pve_user, "root")
  pve_ssh_private_key = try(local.secrets_data.pve_ssh_private_key, "")
  pve_ssh_port        = try(local.secrets_data.pve_ssh_port, 22)

  containers = local.all_containers
}

# Outputs
output "deployed_containers" {
  description = "List of deployed containers"
  value       = keys(local.all_containers)
}

output "network_config" {
  description = "Network configuration from manifest"
  value       = local.network_config
}

output "manifest_summary" {
  description = "Summary of manifest data"
  value = {
    total_services = parseint(local.manifest.total_services, 10)
    network_domain = local.manifest.network_domain
    network_cidr = local.manifest.network_cidr
  }
}
