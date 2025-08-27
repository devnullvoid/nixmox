# Simplified Terraform Manifest Reader
# Outputs only string values for Terraform external data source
# Usage: nix eval -f terraform/manifest-simple.nix --json

let
  # Import the service manifest
  manifest = import ../nixos/service-manifest.nix;
  
  # Extract network configuration
  network = manifest.network or {};
  
  # Extract core services
  coreServices = manifest.core_services or {};
  
  # Extract application services
  appServices = manifest.services or {};
  
  # All services combined
  allServices = coreServices // appServices;
  
  # Convert container specs to JSON strings
  containersToJson = services:
    builtins.toJSON (builtins.mapAttrs (serviceName: serviceConfig: {
      vmid = serviceConfig.vmid or 900;
      hostname = serviceConfig.hostname or "${serviceName}.${network.domain}";
      cores = serviceConfig.resources.cores or 2;
      memory = serviceConfig.resources.memory or 2048;
      disk_gb = serviceConfig.resources.disk_gb or 16;
      ip = serviceConfig.ip;
      gw = network.gateway;
      vlan_tag = toString (network.vlan_tag or 99);
      onboot = serviceConfig.onboot or true;
      start = serviceConfig.start or true;
    }) services);
  
  # Convert network config to JSON string
  networkToJson = builtins.toJSON {
    dns_server = network.dns_server or "192.168.99.13";
    gateway = network.gateway or "192.168.99.1";
    network_cidr = network.network_cidr or "192.168.99.0/24";
    vlan_tag = network.vlan_tag or 99;
    domain = network.domain or "nixmox.lan";
  };
  
  # Convert DNS records to JSON string
  dnsRecordsToJson = builtins.toJSON (builtins.mapAttrs (name: config: {
    domain = config.hostname;
    ip = config.ip;
  }) allServices);
  
  # Generate OIDC application configurations from manifest
  generateOIDCApps = 
    builtins.toJSON (builtins.mapAttrs (name: config: {
      name = name;
      domain = config.interface.proxy.domain;
      oidc_client_id = config.interface.auth.oidc.client_id or "${name}-oidc";
      oidc_client_type = config.interface.auth.oidc.client_type or "confidential";
      oidc_scopes = config.interface.auth.oidc.scopes or ["openid" "email" "profile"];
      redirect_uris = config.interface.auth.oidc.redirect_uris or [];
      launch_url = "https://${config.interface.proxy.domain}";
      open_in_new_tab = true;
    }) (builtins.removeAttrs appServices ["monitoring" "mail"]));
  
  # Generate outpost configuration from manifest
  generateOutpostConfig = builtins.toJSON {
    ldap = network.outposts.ldap or {};
    radius = network.outposts.radius or {};
  };
  
in {
  # Container specifications as JSON strings
  phase1_containers = containersToJson (builtins.removeAttrs allServices ["vaultwarden" "guacamole" "monitoring" "nextcloud" "media" "mail"]);
  phase2_containers = containersToJson (builtins.removeAttrs allServices ["postgresql" "dns" "caddy" "vaultwarden" "guacamole" "monitoring" "nextcloud" "media" "mail"]);
  phase3_containers = containersToJson (builtins.removeAttrs allServices ["postgresql" "dns" "caddy" "authentik"]);
  
  # Network configuration as JSON string
  network_config = networkToJson;
  
  # DNS records as JSON string
  dns_records = dnsRecordsToJson;
  
  # Service count
  total_services = toString (builtins.length (builtins.attrNames allServices));
  phase1_count = toString (builtins.length (builtins.attrNames (builtins.removeAttrs allServices ["vaultwarden" "guacamole" "monitoring" "nextcloud" "media" "mail"])));
  phase2_count = toString (builtins.length (builtins.attrNames (builtins.removeAttrs allServices ["postgresql" "dns" "caddy" "vaultwarden" "guacamole" "monitoring" "nextcloud" "media" "mail"])));
  phase3_count = toString (builtins.length (builtins.attrNames (builtins.removeAttrs allServices ["postgresql" "dns" "caddy" "authentik"])));
  
  # Network info
  network_domain = network.domain or "nixmox.lan";
  network_cidr = network.network_cidr or "192.168.99.0/24";
  network_gateway = network.gateway or "192.168.99.1";
  network_vlan = toString (network.vlan_tag or 99);
  
  # Authentik configurations
  oidc_apps = generateOIDCApps;
  outpost_config = generateOutpostConfig;
  
  # Authentik service info
  authentik_url = "http://${coreServices.authentik.ip}:9000";
}
