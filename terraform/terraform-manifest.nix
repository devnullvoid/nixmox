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
      filteredByArgs = if deploymentArgs.onlyServices != null then
        # Only deploy specified services
        builtins.filter (serviceName: builtins.elem serviceName deploymentArgs.onlyServices) candidateServices
      else if deploymentArgs.skipServices != [] then
        # Skip specified services
        builtins.filter (serviceName: !builtins.elem serviceName deploymentArgs.skipServices) candidateServices
      else
        candidateServices;

      # Apply incremental filtering (only missing/changed services)
      filteredByState = if incrementalMode then
        let
          comparison = deploymentState.compareManifestWithState manifest currentState;
        in
        builtins.filter (serviceName:
          builtins.elem serviceName comparison.containers_to_create ||
          builtins.elem serviceName comparison.services_to_deploy ||
          builtins.elem serviceName deploymentArgs.forceRedeploy
        ) filteredByArgs
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
    }) filteredServiceConfigs);
  
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
      filteredOIDCServices = if incrementalMode then
        let
          comparison = deploymentState.compareManifestWithState manifest currentState;
        in
        builtins.filter (serviceName:
          builtins.elem serviceName comparison.oidc_apps_to_create ||
          builtins.elem serviceName deploymentArgs.forceRedeploy
        ) oidcServices
      else
        oidcServices;
    in
    builtins.toJSON (builtins.listToAttrs (map (name: {
      name = name;
      value = let config = appServices.${name}; in {
        name = name;
        domain = config.interface.proxy.domain;
        oidc_client_id = config.interface.auth.oidc.client_id or "${name}-oidc";
        oidc_client_type = config.interface.auth.oidc.client_type or "confidential";
        oidc_scopes = config.interface.auth.oidc.scopes or ["openid" "email" "profile"];
        redirect_uris = config.interface.auth.oidc.redirect_uris or [];
        launch_url = "https://${config.interface.proxy.domain}";
        open_in_new_tab = true;
      };
    }) filteredOIDCServices));
  
  # Generate outpost configuration from manifest
  generateOutpostConfig = builtins.toJSON {
    ldap = network.outposts.ldap or {};
    radius = network.outposts.radius or {};
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
  
  # Authentik service info
  authentik_url = "http://${coreServices.authentik.ip}:9000";

  # Deployment planning information
  deployment_plan = if incrementalMode then
    let
      comparison = deploymentState.compareManifestWithState manifest currentState;
      plan = deploymentState.generateDeploymentPlan manifest currentState;
    in {
      summary = comparison.summary;
      containers_to_create = comparison.containers_to_create;
      oidc_apps_to_create = comparison.oidc_apps_to_create;
      nixos_redeployments = comparison.nixos_redeployments;
      execution_order = plan.execution_order;
    }
  else {
    summary = {
      total_services_in_manifest = builtins.length (builtins.attrNames allServices);
      services_already_deployed = 0;
      services_needing_deployment = builtins.length (builtins.attrNames allServices);
      containers_needing_creation = builtins.length (builtins.attrNames allServices);
      oidc_apps_needing_creation = builtins.length (builtins.attrNames (builtins.fromJSON generateOIDCApps));
      nixos_redeployments_needed = builtins.length (builtins.attrNames allServices);
    };
    containers_to_create = builtins.attrNames allServices;
    oidc_apps_to_create = builtins.attrNames (builtins.fromJSON generateOIDCApps);
    nixos_redeployments = builtins.attrNames allServices;
    execution_order = builtins.attrNames allServices;
  };
}
