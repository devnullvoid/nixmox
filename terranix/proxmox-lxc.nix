{ lib, ... }:
{
  terraform = {
    required_version = ">= 1.5.0";
    required_providers.proxmox = {
      source = "bpg/proxmox";
      version = ">= 0.56.0";
    };
  };

  provider.proxmox = {
    endpoint = "${var.proxmox_url}";
    username = "${var.proxmox_username}";
    password = "${var.proxmox_password}";
    insecure = var.proxmox_insecure;
    ssh = {
      agent = true;
    };
  };

  variable = {
    # Proxmox connection
    proxmox_url = { type = "string"; description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"; };
    proxmox_username = { type = "string"; description = "Proxmox username (e.g., root@pam)"; };
    proxmox_password = { type = "string"; sensitive = true; description = "Proxmox password"; };
    proxmox_insecure = { type = "bool"; default = true; description = "Allow self-signed TLS certificates"; };

    # Network configuration
    network_bridge = { type = "string"; default = "vmbr0"; description = "Network bridge for containers"; };
    network_gateway = { type = "string"; description = "Network gateway IP"; };
    network_dns = { type = "string"; default = "1.1.1.1"; description = "DNS server IP"; };
    network_cidr = { type = "string"; default = "24"; description = "Network CIDR"; };

    # Storage configuration
    storage_pool = { type = "string"; default = "local-lvm"; description = "Storage pool for container images"; };
    storage_images = { type = "string"; default = "local"; description = "Storage pool for container images"; };

    # Container defaults
    container_cpus = { type = "number"; default = 2; description = "Default CPU cores per container"; };
    container_memory = { type = "number"; default = 2048; description = "Default memory in MB per container"; };
    container_disk = { type = "number"; default = 8; description = "Default disk size in GB per container"; };
    container_swap = { type = "number"; default = 512; description = "Default swap size in MB per container"; };

    # Proxmox node and template
    proxmox_node_name = { type = "string"; description = "Name of the Proxmox node to deploy to"; };
    nixos_template_id = { type = "string"; description = "ID of the NixOS LXC template to use"; };

    # Container credentials
    container_root_password = { type = "string"; sensitive = true; description = "Root password for containers"; };
    container_ssh_keys = { type = "string"; description = "SSH public keys for container access"; };
  };

  # Data sources for existing resources
  data = {
    proxmox_virtual_environment_nodes = {
      available = {
        node_name = var.proxmox_node_name;
      };
    };

    proxmox_virtual_environment_storage_classes = {
      available = {
        node_name = var.proxmox_node_name;
        content_type = "rootdir";
      };
    };
  };

  # Base container configurations
  resource = {
    # Caddy reverse proxy container
    proxmox_virtual_environment_container.caddy = {
      node_name = var.proxmox_node_name;
      vm_id = 100;
      name = "caddy";
      description = "Caddy reverse proxy and TLS termination";
      tags = ["nixos", "infra", "core"];

      # Container specifications
      cores = var.container_cpus;
      memory = var.container_memory;
      swap = var.container_swap;
      disk = {
        datastore_id = var.storage_pool;
        size = var.container_disk;
      };

      # Network configuration
      network_interface = {
        name = "eth0";
        bridge = var.network_bridge;
        ip_address = "10.10.0.10";
        ip_gateway = var.network_gateway;
        ip_cidr = var.network_cidr;
      };

      # NixOS configuration
      initialization = {
        hostname = "caddy.nixmox.lan";
        dns = var.network_dns;
        user_account = {
          username = "root";
          password = var.container_root_password;
          ssh_keys = var.container_ssh_keys;
        };
      };

      # Operating system
      operating_system = {
        type = "l26";
        template_file_id = var.nixos_template_id;
      };

      # Start on boot
      startup = {
        order = 1;
        up_delay = 30;
        down_delay = 30;
      };
    };

    # PostgreSQL database container
    proxmox_virtual_environment_container.postgresql = {
      node_name = var.proxmox_node_name;
      vm_id = 101;
      name = "postgresql";
      description = "PostgreSQL database server";
      tags = ["nixos", "infra", "database"];

      cores = var.container_cpus;
      memory = var.container_memory;
      swap = var.container_swap;
      disk = {
        datastore_id = var.storage_pool;
        size = var.container_disk;
      };

      network_interface = {
        name = "eth0";
        bridge = var.network_bridge;
        ip_address = "10.10.0.11";
        ip_gateway = var.network_gateway;
        ip_cidr = var.network_cidr;
      };

      initialization = {
        hostname = "postgresql.nixmox.lan";
        dns = var.network_dns;
        user_account = {
          username = "root";
          password = var.container_root_password;
          ssh_keys = var.container_ssh_keys;
        };
      };

      operating_system = {
        type = "l26";
        template_file_id = var.nixos_template_id;
      };

      startup = {
        order = 2;
        up_delay = 30;
        down_delay = 30;
      };
    };

    # Authentik identity provider container
    proxmox_virtual_environment_container.authentik = {
      node_name = var.proxmox_node_name;
      vm_id = 102;
      name = "authentik";
      description = "Authentik identity provider";
      tags = ["nixos", "infra", "auth"];

      cores = var.container_cpus;
      memory = var.container_memory;
      swap = var.container_swap;
      disk = {
        datastore_id = var.storage_pool;
        size = var.container_disk;
      };

      network_interface = {
        name = "eth0";
        bridge = var.network_bridge;
        ip_address = "10.10.0.12";
        ip_gateway = var.network_gateway;
        ip_cidr = var.network_cidr;
      };

      initialization = {
        hostname = "authentik.nixmox.lan";
        dns = var.network_dns;
        user_account = {
          username = "root";
          password = var.container_root_password;
          ssh_keys = var.container_ssh_keys;
        };
      };

      operating_system = {
        type = "l26";
        template_file_id = var.nixos_template_id;
      };

      startup = {
        order = 3;
        up_delay = 30;
        down_delay = 30;
      };
    };

    # DNS container
    proxmox_virtual_environment_container.dns = {
      node_name = var.proxmox_node_name;
      vm_id = 103;
      name = "dns";
      description = "DNS server (Unbound)";
      tags = ["nixos", "infra", "core"];

      cores = var.container_cpus;
      memory = var.container_memory;
      swap = var.container_swap;
      disk = {
        datastore_id = var.storage_pool;
        size = var.container_disk;
      };

      network_interface = {
        name = "eth0";
        bridge = var.network_bridge;
        ip_address = "10.10.0.13";
        ip_gateway = var.network_gateway;
        ip_cidr = var.network_cidr;
      };

      initialization = {
        hostname = "dns.nixmox.lan";
        dns = var.network_dns;
        user_account = {
          username = "root";
          password = var.container_root_password;
          ssh_keys = var.container_ssh_keys;
        };
      };

      operating_system = {
        type = "l26";
        template_file_id = var.nixos_template_id;
      };

      startup = {
        order = 4;
        up_delay = 30;
        down_delay = 30;
      };
    };
  };

  # Outputs for deployment status
  output = {
    caddy_container_id = {
      description = "ID of the Caddy container";
      value = lib.terraformRef "proxmox_virtual_environment_container.caddy.id";
    };

    postgresql_container_id = {
      description = "ID of the PostgreSQL container";
      value = lib.terraformRef "proxmox_virtual_environment_container.postgresql.id";
    };

    authentik_container_id = {
      description = "ID of the Authentik container";
      value = lib.terraformRef "proxmox_virtual_environment_container.authentik.id";
    };

    dns_container_id = {
      description = "ID of the DNS container";
      value = lib.terraformRef "proxmox_virtual_environment_container.dns.id";
    };

    infrastructure_ready = {
      description = "Whether the infrastructure containers are ready";
      value = true;
    };
  };
}
