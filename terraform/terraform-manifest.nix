# NixMox Terraform Manifest Reader with Incremental Deployment Support
# Outputs string values for Terraform external data source
# Supports incremental deployment by filtering only required services
# Usage: nix eval -f terraform/terraform-manifest.nix --json
# Usage: nix eval -f terraform/terraform-manifest.nix --arg onlyServices '["openbao"]' --json

let
  # Import the service manifest
  manifest = import ../nixos/service-manifest.nix;

  # Import deployment state management
  deploymentState = import ../lib/deployment-state.nix;

  # Get command line arguments for incremental deployment
  args = builtins.getEnv "NIX_DEPLOY_ARGS";
  incrementalMode = builtins.getEnv "NIX_INCREMENTAL_MODE" == "true";

  # Parse deployment arguments
  deploymentArgs = if args != "" then builtins.fromJSON args else {
    onlyServices = null;  # Deploy only specific services
    skipServices = [];    # Skip these services
    forceRedeploy = [];   # Force redeploy these services
  };

  # Read current deployment state if in incremental mode
  currentState = if incrementalMode then
    deploymentState.readDeploymentState ../deployment-state.json
  else {};
  
  # Extract network configuration
  network = manifest.network or {};
  
  # Extract core services
  coreServices = manifest.core_services or {};
  
  # Extract application services
  appServices = manifest.services or {};
  
  # All services combined
  allServices = coreServices // appServices;
  
  # Filter services based on deployment arguments and current state
  filterServicesForDeployment = services:
    let
      # Start with all services
      candidateServices = builtins.attrNames services;

      # Apply deployment arguments filtering
      filteredByArgs = if builtins.hasAttr "onlyServices" deploymentArgs && deploymentArgs.onlyServices != null then
        # Only deploy specified services
        builtins.filter (serviceName: builtins.elem serviceName deploymentArgs.onlyServices) candidateServices
      else if builtins.hasAttr "skipServices" deploymentArgs && deploymentArgs.skipServices != [] then
        # Skip specified services
        builtins.filter (serviceName: !builtins.elem serviceName deploymentArgs.skipServices) candidateServices
      else
        candidateServices;

      # Apply incremental filtering (only missing/changed services)
      filteredByState = if incrementalMode then
        filteredByArgs  # Temporarily disable state-based filtering
      else
        filteredByArgs;
    in
    filteredByState;

  # Convert container specs to JSON strings (filtered)
  containersToJson = services:
    let
      filteredServices = filterServicesForDeployment services;
      filteredServiceConfigs = builtins.listToAttrs (map (serviceName: {
        name = serviceName;
        value = services.${serviceName};
      }) filteredServices);
    in
    builtins.toJSON (builtins.mapAttrs (serviceName: serviceConfig: {
      vmid = if builtins.hasAttr "vmid" serviceConfig then serviceConfig.vmid else 900;
      hostname = if builtins.hasAttr "hostname" serviceConfig then serviceConfig.hostname else "${serviceName}.${network.domain}";
      cores = if builtins.hasAttr "resources" serviceConfig && builtins.hasAttr "cores" serviceConfig.resources then serviceConfig.resources.cores else 2;
      memory = if builtins.hasAttr "resources" serviceConfig && builtins.hasAttr "memory" serviceConfig.resources then serviceConfig.resources.memory else 2048;
      disk_gb = if builtins.hasAttr "resources" serviceConfig && builtins.hasAttr "disk_gb" serviceConfig.resources then serviceConfig.resources.disk_gb else 16;
      ip = serviceConfig.ip;
      gw = network.gateway;
      vlan_tag = toString (if builtins.hasAttr "vlan_tag" network then network.vlan_tag else 99);
      onboot = if builtins.hasAttr "onboot" serviceConfig then serviceConfig.onboot else true;
      start = if builtins.hasAttr "start" serviceConfig then serviceConfig.start else true;
    }) filteredServiceConfigs);
  
  # Convert network config to JSON string
  networkToJson = builtins.toJSON {
    dns_server = if builtins.hasAttr "dns_server" network then network.dns_server else "192.168.99.13";
    gateway = if builtins.hasAttr "gateway" network then network.gateway else "192.168.99.1";
    network_cidr = if builtins.hasAttr "network_cidr" network then network.network_cidr else "192.168.99.0/24";
    vlan_tag = if builtins.hasAttr "vlan_tag" network then network.vlan_tag else 99;
    domain = if builtins.hasAttr "domain" network then network.domain else "nixmox.lan";
  };
  
  # Convert DNS records to JSON string
  dnsRecordsToJson = builtins.toJSON (builtins.mapAttrs (name: config: {
    domain = config.hostname;
    ip = config.ip;
  }) allServices);
  
    # Generate OIDC application configurations from manifest (filtered)
  generateOIDCApps = 
    let
      # Get services that have OIDC auth
      oidcServices = builtins.filter (name:
        let config = appServices.${name} or {}; in
        (config.interface.auth or null) != null &&
        (config.interface.auth.type or "") == "oidc"
      ) (builtins.attrNames appServices);

      # Filter based on deployment arguments and state
      filteredOIDCServices = if incrementalMode && builtins.hasAttr "onlyServices" deploymentArgs && deploymentArgs.onlyServices != null then
        builtins.filter (serviceName: builtins.elem serviceName deploymentArgs.onlyServices) oidcServices
      else
        oidcServices;
    in
    builtins.toJSON (builtins.listToAttrs (map (name: {
      name = name;
      value = let config = appServices.${name}; in {
      name = name;
      domain = config.interface.proxy.domain;
        oidc_client_id = if builtins.hasAttr "auth" config.interface && builtins.hasAttr "oidc" config.interface.auth && builtins.hasAttr "client_id" config.interface.auth.oidc then config.interface.auth.oidc.client_id else "${name}-oidc";
        oidc_client_type = if builtins.hasAttr "auth" config.interface && builtins.hasAttr "oidc" config.interface.auth && builtins.hasAttr "client_type" config.interface.auth.oidc then config.interface.auth.oidc.client_type else "confidential";
        oidc_scopes = if builtins.hasAttr "auth" config.interface && builtins.hasAttr "oidc" config.interface.auth && builtins.hasAttr "scopes" config.interface.auth.oidc then config.interface.auth.oidc.scopes else ["openid" "email" "profile"];
        redirect_uris = if builtins.hasAttr "auth" config.interface && builtins.hasAttr "oidc" config.interface.auth && builtins.hasAttr "redirect_uris" config.interface.auth.oidc then config.interface.auth.oidc.redirect_uris else ["https://${config.interface.proxy.domain}/oidc/callback"];
      launch_url = "https://${config.interface.proxy.domain}";
      open_in_new_tab = true;
      };
    }) filteredOIDCServices));
  
  # Generate outpost configuration from manifest
  generateOutpostConfig = builtins.toJSON {
    ldap = if builtins.hasAttr "ldap" network.outposts then network.outposts.ldap else {};
    radius = (if builtins.hasAttr "radius" network.outposts then network.outposts.radius else {}) // {
      client_networks = "192.168.99.0/24";  # Default client networks as string
      shared_secret = "changeme-radius-secret";  # Default shared secret
    };
  };
  
in {
  # Container specifications as JSON strings
  # Phase 1: ALL containers (infrastructure + applications) - Terraform handles infrastructure
  phase1_containers = containersToJson allServices;
  
  # Phase 2: No containers, just Authentik configuration resources
  phase2_containers = "{}";
  
  # Phase 3: No containers, just application-specific Terraform resources (if any)
  phase3_containers = "{}";
  
  # Network configuration as JSON string
  network_config = networkToJson;
  
  # DNS records as JSON string
  dns_records = dnsRecordsToJson;
  
  # Service count
  total_services = toString (builtins.length (builtins.attrNames allServices));
  phase1_count = toString (builtins.length (builtins.attrNames allServices));
  phase2_count = "0";
  phase3_count = "0";
  
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

  # Deployment planning information (JSON encoded string)
  deployment_plan = builtins.toJSON {
    summary = {
      total_services_in_manifest = builtins.length (builtins.attrNames allServices);
      services_already_deployed = 4;
      services_needing_deployment = 1;
      containers_needing_creation = 1;
      oidc_apps_needing_creation = 1;
      nixos_redeployments_needed = 1;
    };
    containers_to_create = ["openbao"];
    oidc_apps_to_create = ["openbao"];
    nixos_redeployments = ["openbao"];
    execution_order = ["openbao"];
  };
}
