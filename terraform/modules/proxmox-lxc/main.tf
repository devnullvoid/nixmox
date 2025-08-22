terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 2.9"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "proxmox" {
  # Fill from environment or TF var files
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = var.pm_tls_insecure
}

variable "pm_api_url" {}
variable "pm_api_token_id" {}
variable "pm_api_token_secret" {}
variable "pm_tls_insecure" { default = false }

variable "node" { type = string }
variable "pool" { type = string }
variable "bridge" { type = string }
variable "cidr" { type = string }
variable "storage" { type = string }

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
  description = "If set, this is the Proxmox template storage path of the Hydra NixOS LXC template (e.g., local:vztmpl/nixos-25.05-x86_64-linux.tar.xz). If empty, will download to local storage and use that."
  type        = string
  default     = ""
}

variable "nixos_version" {
  description = "NixOS version to download from Hydra when hydra_template is empty (e.g., 25.05)"
  type        = string
  default     = "25.05"
}

variable "containers" {
  description = "Map of containers to create"
  type = map(object({
    vmid       = number
    hostname   = string
    cores      = number
    memory     = number
    disk_gb    = number
    ip         = string
    gw         = string
    vlan_tag   = optional(string)
  }))
}

# Connection to Proxmox node for pct operations
variable "pve_host" {
  description = "Proxmox host for pct operations"
  type        = string
}

variable "pve_user" {
  description = "SSH user on Proxmox host"
  type        = string
  default     = "root"
}

variable "pve_ssh_private_key" {
  description = "SSH private key contents for Proxmox host"
  type        = string
}

variable "pve_ssh_port" {
  description = "SSH port on Proxmox host"
  type        = number
  default     = 22
}

# Ensure Hydra template exists on the Proxmox node (download if not provided)
resource "null_resource" "ensure_template" {
  count = var.hydra_template == "" ? 1 : 0

  triggers = {
    version = var.nixos_version
  }

  connection {
    host        = var.pve_host
    user        = var.pve_user
    port        = var.pve_ssh_port
    private_key = var.pve_ssh_private_key
  }

  provisioner "file" {
    content = <<-EOT
      #!/usr/bin/env bash
      set -euo pipefail
      tmpl_dir=/var/lib/vz/template/cache
      tmpl_name=nixos-${var.nixos_version}-x86_64-linux.tar.xz
      url=https://hydra.nixos.org/job/nixos/release-${var.nixos_version}/nixos.proxmoxLXC.x86_64-linux/latest/download-by-type/file/system-tarball
      mkdir -p "$tmpl_dir"
      if [ ! -f "$tmpl_dir/$tmpl_name" ]; then
        wget -O "$tmpl_dir/$tmpl_name" "$url"
      fi
    EOT
    destination = "/root/ensure_template.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -lc 'chmod +x /root/ensure_template.sh'",
      "bash -lc '[ \"$(id -u)\" -eq 0 ] && /root/ensure_template.sh || sudo -n /root/ensure_template.sh'"
    ]
  }
}

locals {
  template_path = var.hydra_template != "" ? var.hydra_template : "local:vztmpl/nixos-${var.nixos_version}-x86_64-linux.tar.xz"
}

resource "proxmox_lxc" "container" {
  for_each = var.containers
  target_node = var.node
  pool        = var.pool != "" ? var.pool : null

  vmid      = each.value.vmid
  hostname  = each.value.hostname
  ostemplate = local.template_path
  password  = "changeme"
  cores     = each.value.cores
  memory    = each.value.memory
  ssh_public_keys = var.ssh_public_keys

  rootfs {
    storage = var.storage
    size    = format("%dG", each.value.disk_gb)
  }

  network {
    name   = "eth0"
    bridge = var.bridge
    ip     = "${each.value.ip}/24"
    gw     = each.value.gw
    tag    = try(each.value.vlan_tag, null)
  }

  start = true
  
  features {
    nesting = true
  }

  # Ensure unprivileged container (required for nesting and better Nix behavior in LXC)
  unprivileged = true
  depends_on = [null_resource.ensure_template]
}

# Push minimal configuration.nix using pct, then run nixos-rebuild inside the container without SSH
resource "null_resource" "bootstrap_config" {
  for_each = var.containers

  triggers = {
    vmid     = each.value.vmid
    hostname = each.value.hostname
    ip       = each.value.ip
    nixos_version = var.nixos_version
    ssh_key  = var.ssh_public_keys
  }

  connection {
    host        = var.pve_host
    user        = var.pve_user
    port        = var.pve_ssh_port
    private_key = var.pve_ssh_private_key
  }

  # Render template locally and upload to Proxmox node, then pct push and exec
  provisioner "file" {
    content     = templatefile("${path.module}/templates/configuration.nix.tmpl", {
      hostname           = self.triggers.hostname
      nixos_version      = self.triggers.nixos_version
      privileged         = "false"
      ssh_authorized_key = self.triggers.ssh_key
      ip                 = self.triggers.ip
      gw                 = each.value.gw
    })
    destination = "/root/configuration.${self.triggers.vmid}.nix"
  }

  provisioner "file" {
    content = <<-EOT
      #!/usr/bin/env bash
      set -euo pipefail
      pct push ${self.triggers.vmid} /root/configuration.${self.triggers.vmid}.nix /etc/nixos/configuration.nix
      
      # Follow the official NixOS Proxmox LXC setup procedure:
      # 1. First run nix-channel --update to ensure channels are available
      # 2. Then run nixos-rebuild switch --upgrade
      echo "Running nix-channel --update..."
      pct exec ${self.triggers.vmid} -- sh -lc 'source /etc/set-environment; nix-channel --update'
      
      echo "Running nixos-rebuild switch --upgrade..."
      pct exec ${self.triggers.vmid} -- sh -lc 'source /etc/set-environment; nixos-rebuild switch --upgrade'
      
      echo "Bootstrap complete for ${self.triggers.hostname} (VMID: ${self.triggers.vmid})"
    EOT
    destination = "/root/bootstrap_nixos_${self.triggers.vmid}.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -lc 'chmod +x /root/bootstrap_nixos_${self.triggers.vmid}.sh'",
      "bash -lc '[ \"$(id -u)\" -eq 0 ] && /root/bootstrap_nixos_${self.triggers.vmid}.sh || sudo -n /root/bootstrap_nixos_${self.triggers.vmid}.sh'"
    ]
  }

  depends_on = [proxmox_lxc.container]
}

# Optional post-create deploy using nixos-rebuild from the local machine running Terraform
resource "null_resource" "deploy" {
  for_each = var.provision_with_rebuild ? var.containers : {}

  triggers = {
    vmid     = each.value.vmid
    hostname = each.value.hostname
    ip       = each.value.ip
    flake    = length(var.flake_root) > 0 ? var.flake_root : abspath("${path.module}/../../../..")
  }

  provisioner "local-exec" {
    command = "bash -lc 'set -e; echo Waiting for SSH on ${self.triggers.ip}...; for i in $(seq 1 60); do if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@${self.triggers.ip} true 2>/dev/null; then break; fi; sleep 2; done; if command -v nixos-rebuild >/dev/null 2>&1; then nixos-rebuild switch --fast --flake ${self.triggers.flake}#${self.triggers.hostname} --target-host root@${self.triggers.ip}; else nix run nixpkgs#nixos-rebuild -- switch --fast --flake ${self.triggers.flake}#${self.triggers.hostname} --target-host root@${self.triggers.ip}; fi'"
  }

  depends_on = [proxmox_lxc.container, null_resource.bootstrap_config]
}
