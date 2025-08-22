terraform {
  required_version = ">= 1.6.0"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

provider "sops" {}

# Deployment phase control
variable "deployment_phase" {
  description = "Deployment phase (1=infrastructure, 2=core, 3=applications, 4=advanced)"
  type        = number
  default     = 1
  validation {
    condition     = var.deployment_phase >= 1 && var.deployment_phase <= 4
    error_message = "Deployment phase must be between 1 and 4."
  }
}

# Environment variable
variable "environment" {
  description = "Environment to deploy (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# SOPS secrets file - make it optional
variable "secrets_file" {
  description = "Path to SOPS encrypted secrets file"
  type        = string
  default     = ""
}

# Proxmox API configuration - make these required if no secrets file
variable "pm_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = ""
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
  default     = ""
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pm_tls_insecure" {
  description = "Allow insecure TLS connections to Proxmox"
  type        = bool
  default     = false
}

# Infrastructure configuration
variable "node" {
  description = "Proxmox node name"
  type        = string
  default     = "proxmox"
}

variable "pool" {
  description = "Proxmox resource pool"
  type        = string
  default     = "nixmox"
}

variable "bridge" {
  description = "Network bridge for containers"
  type        = string
  default     = "vmbr0"
}

variable "cidr" {
  description = "Network CIDR for containers"
  type        = string
  default     = "10.10.0.0/24"
}

variable "storage" {
  description = "Storage pool for containers"
  type        = string
  default     = "local-lvm"
}

# SSH and deployment configuration
variable "ssh_public_keys" {
  description = "SSH public keys to inject into LXC (authorized_keys)"
  type        = string
  default     = ""
}

variable "provision_with_rebuild" {
  description = "If true, runs nixos-rebuild switch against each container after creation"
  type        = bool
  default     = false
}

variable "flake_root" {
  description = "Path to the flake root used in nixos-rebuild --flake <path>#<host>"
  type        = string
  default     = ""
}

variable "hydra_template" {
  description = "If set, this is the Proxmox template storage path of the Hydra NixOS LXC template"
  type        = string
  default     = ""
}

variable "nixos_version" {
  description = "NixOS version to download from Hydra when hydra_template is empty"
  type        = string
  default     = "25.05"
}

# Proxmox SSH connection
variable "pve_host" {
  description = "Proxmox host for SSH operations"
  type        = string
  default     = ""
}

variable "pve_user" {
  description = "SSH user on Proxmox host"
  type        = string
  default     = "root"
}

variable "pve_ssh_private_key" {
  description = "SSH private key contents for Proxmox host"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pve_ssh_port" {
  description = "SSH port on Proxmox host"
  type        = number
  default     = 22
}

# Authentik configuration
variable "authentik_bootstrap_token" {
  description = "Authentik bootstrap token for API access"
  type        = string
  default     = ""
}

# Environment-specific configurations
locals {
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

  # Container definitions by phase
  phase1_containers = {
    postgresql = {
      vmid = 202
      hostname = "postgresql"
      cores = 4
      memory = 2048
      disk_gb = 20
      ip = "10.10.0.11"
      gw = "10.10.0.1"
    }
    caddy = {
      vmid = 201
      hostname = "caddy"
      cores = 2
      memory = 1024
      disk_gb = 8
      ip = "10.10.0.10"
      gw = "10.10.0.1"
    }
  }

  phase2_containers = {
    authentik = {
      vmid = 203
      hostname = "authentik"
      cores = 2
      memory = 2048
      disk_gb = 16
      ip = "10.10.0.12"
      gw = "10.10.0.1"
    }
    dns = {
      vmid = 204
      hostname = "dns"
      cores = 1
      memory = 512
      disk_gb = 8
      ip = "10.10.0.13"
      gw = "10.10.0.1"
    }
  }

  phase3_containers = {
    vaultwarden = {
      vmid = 205
      hostname = "vaultwarden"
      cores = 2
      memory = 1024
      disk_gb = 16
      ip = "10.10.0.14"
      gw = "10.10.0.1"
    }
    nextcloud = {
      vmid = 206
      hostname = "nextcloud"
      cores = 4
      memory = 4096
      disk_gb = 32
      ip = "10.10.0.15"
      gw = "10.10.0.1"
    }
    guacamole = {
      vmid = 207
      hostname = "guacamole"
      cores = 2
      memory = 2048
      disk_gb = 16
      ip = "10.10.0.16"
      gw = "10.10.0.1"
    }
    media = {
      vmid = 208
      hostname = "media"
      cores = 2
      memory = 2048
      disk_gb = 32
      ip = "10.10.0.17"
      gw = "10.10.0.1"
    }
    monitoring = {
      vmid = 209
      hostname = "monitoring"
      cores = 2
      memory = 1024
      disk_gb = 16
      ip = "10.10.0.18"
      gw = "10.10.0.1"
    }
    mail = {
      vmid = 210
      hostname = "mail"
      cores = 2
      memory = 1024
      disk_gb = 16
      ip = "10.10.0.19"
      gw = "10.10.0.1"
    }
  }

  # Merge containers based on deployment phase
  containers_to_deploy = merge(
    var.deployment_phase >= 1 ? local.phase1_containers : {},
    var.deployment_phase >= 2 ? local.phase2_containers : {},
    var.deployment_phase >= 3 ? local.phase3_containers : {}
  )
}

# SOPS data source - only create if secrets file is provided
data "sops_file" "secrets" {
  count = var.secrets_file != "" ? 1 : 0
  source_file = var.secrets_file
}

module "lxc" {
  source = "../modules/proxmox-lxc"

  pm_api_url          = try(local.secrets_data.pm_api_url, var.pm_api_url)
  pm_api_token_id     = try(local.secrets_data.pm_api_token_id, var.pm_api_token_id)
  pm_api_token_secret = try(local.secrets_data.pm_api_token_secret, var.pm_api_token_secret)
  pm_tls_insecure     = try(local.secrets_data.pm_tls_insecure, var.pm_tls_insecure)

  node    = var.node
  pool    = var.pool
  bridge  = var.bridge
  cidr    = var.cidr
  storage = var.storage

  ssh_public_keys        = try(local.secrets_data.ssh_public_keys, var.ssh_public_keys)
  provision_with_rebuild = var.provision_with_rebuild
  flake_root             = try(local.secrets_data.flake_root, var.flake_root)
  hydra_template         = try(local.secrets_data.hydra_template, var.hydra_template)
  nixos_version          = var.nixos_version

  pve_host            = try(local.secrets_data.pve_host, var.pve_host)
  pve_user            = try(local.secrets_data.pve_user, var.pve_user)
  pve_ssh_private_key = try(local.secrets_data.pve_ssh_private_key, var.pve_ssh_private_key)
  pve_ssh_port        = var.pve_ssh_port

  containers = local.containers_to_deploy
}

# Phase 4: Authentik Outposts (only when phase >= 4)
module "authentik_outposts" {
  count  = var.deployment_phase >= 4 ? 1 : 0
  source = "../modules/authentik"

  authentik_url = "http://10.10.0.12:9000"
  authentik_bootstrap_token = try(local.secrets_data.authentik_bootstrap_token, var.authentik_bootstrap_token)
  
  ldap_outpost_config = {
    name = "LDAP Outpost"
    search_base_dn = "dc=nixmox,dc=lan"
    bind_dn = "cn=admin,dc=nixmox,dc=lan"
    bind_password = ""
    search_group = ""
    additional_user_dn = "ou=users"
    additional_group_dn = "ou=groups"
    user_object_filter = "(objectClass=person)"
    group_object_filter = "(objectClass=groupOfNames)"
    group_membership_field = "member"
    object_uniqueness_field = "uid"
  }
  
  radius_outpost_config = {
    name = "RADIUS Outpost"
    shared_secret = "radius_secret"
    client_networks = ["0.0.0.0/0"]
  }
}

# Outputs for each phase
output "deployment_phase" {
  description = "Current deployment phase"
  value       = var.deployment_phase
}

output "phase1_ready" {
  description = "Phase 1 containers deployed"
  value       = var.deployment_phase >= 1
}

output "phase2_ready" {
  description = "Phase 2 containers deployed"
  value       = var.deployment_phase >= 2
}

output "phase3_ready" {
  description = "Phase 3 containers deployed"
  value       = var.deployment_phase >= 3
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

# Phase 4 outputs
output "ldap_outpost_id" {
  description = "LDAP outpost ID for getting view key"
  value       = var.deployment_phase >= 4 ? module.authentik_outposts[0].ldap_outpost_id : null
}

output "radius_outpost_id" {
  description = "RADIUS outpost ID for getting view key"
  value       = var.deployment_phase >= 4 ? module.authentik_outposts[0].radius_outpost_id : null
}

output "authentik_outposts_ready" {
  description = "Whether authentik outposts are deployed"
  value       = var.deployment_phase >= 4
}

# Environment information
output "environment" {
  description = "Current deployment environment"
  value       = var.environment
}

output "resource_multiplier" {
  description = "Resource multiplier for current environment"
  value       = local.current_env.resource_multiplier
}

output "backup_enabled" {
  description = "Whether backups are enabled for current environment"
  value       = local.current_env.backup_enabled
}

output "monitoring_level" {
  description = "Monitoring level for current environment"
  value       = local.current_env.monitoring_level
}
