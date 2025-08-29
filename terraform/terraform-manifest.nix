# NixMox Terraform Manifest Reader
# Outputs string values for Terraform external data source
# Usage: nix eval -f terraform/terraform-manifest.nix --json

let
  # Import the service manifest
  manifest = import ../nixos/service-manifest.nix;

  # Extract network configuration
  network = manifest.network or {};

  # Extract core services (Phase 1)
  coreServices = manifest.core_services or {};

  # Extract application services (Phase 2 & 3)
  appServices = manifest.services or {};

  # All services combined - no more phases, just all services
  allServices = coreServices // appServices;

  # Convert container specs to JSON strings
  containersToJson = services: builtins.toJSON (builtins.mapAttrs (serviceName: serviceConfig: {
    vmid = serviceConfig.vmid or 900;
    hostname = serviceConfig.hostname or "${serviceName}.${network.domain or "nixmox.lan"}";
    cores = if serviceConfig.resources or {} ? cores then serviceConfig.resources.cores else 2;
    memory = if serviceConfig.resources or {} ? memory then serviceConfig.resources.memory else 2048;
    disk_gb = if serviceConfig.resources or {} ? disk_gb then serviceConfig.resources.disk_gb else 16;
    ip = serviceConfig.ip;
    gw = network.gateway or "192.168.99.1";
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
    domain = config.hostname or "${name}.${network.domain or "nixmox.lan"}";
    ip = config.ip;
  }) allServices);

  # Generate OIDC application configurations from manifest
  generateOIDCApps = builtins.toJSON (builtins.listToAttrs (map (name: {
    name = name;
    value = let config = appServices.${name}; in {
      name = name;
      domain = config.interface.proxy.domain;
      oidc_client_id = config.interface.auth.oidc.client_id or "${name}-oidc";
      oidc_client_type = config.interface.auth.oidc.client_type or "confidential";
      oidc_scopes = config.interface.auth.oidc.scopes or ["openid" "email" "profile"];
      redirect_uris = config.interface.auth.oidc.redirect_uris or ["https://${config.interface.proxy.domain}/oidc/callback"];
      launch_url = "https://${config.interface.proxy.domain}";
      open_in_new_tab = true;
    };
  }) (builtins.filter (name:
    let config = appServices.${name} or {}; in
    (config.interface.auth or null) != null &&
    (config.interface.auth.type or "") == "oidc"
  ) (builtins.attrNames appServices))));

  # Generate outpost configuration from manifest
  generateOutpostConfig = builtins.toJSON {
    ldap = if network ? outposts && network.outposts ? ldap then network.outposts.ldap else {};
    radius = (if network ? outposts && network.outposts ? radius then network.outposts.radius else {}) // {
      client_networks = "192.168.99.0/24";
      shared_secret = "changeme-radius-secret";
    };
  };

in {
  # All container specifications as JSON string (no phases)
  all_containers = containersToJson allServices;               # All services

  # Network configuration as JSON string
  network_config = networkToJson;

  # DNS records as JSON string
  dns_records = dnsRecordsToJson;

  # Service counts
  total_services = toString (builtins.length (builtins.attrNames allServices));
  phase1_count = toString (builtins.length (builtins.attrNames coreServices));
  phase2_count = "0";
  phase3_count = toString (builtins.length (builtins.attrNames appServices));

  # Network info
  network_domain = network.domain or "nixmox.lan";
  network_cidr = network.network_cidr or "192.168.99.0/24";
  network_gateway = network.gateway or "192.168.99.1";
  network_vlan = toString (network.vlan_tag or 99);

  # Authentik configurations
  oidc_apps = generateOIDCApps;
  outpost_config = generateOutpostConfig;

  # LDAP and RADIUS app configurations
  ldap_app = builtins.toJSON {
    name = "LDAP";
    slug = "ldap";
    meta_description = "LDAP authentication service";
    meta_launch_url = "";
    open_in_new_tab = false;
  };
  radius_app = builtins.toJSON {
    name = "RADIUS";
    slug = "radius";
    meta_description = "RADIUS authentication service";
    meta_launch_url = "";
    open_in_new_tab = false;
  };

  # Authentik service info
  authentik_url = "http://${coreServices.authentik.ip}:9000";
}
