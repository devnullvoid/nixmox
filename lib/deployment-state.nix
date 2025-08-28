# NixMox Deployment State Management
# This module provides functions to track and manage deployment state
# for incremental deployments

let
  # Read deployment state from a JSON file
  readDeploymentState = stateFile:
    if builtins.pathExists stateFile
    then builtins.fromJSON (builtins.readFile stateFile)
    else {
      # Initial state structure
      version = "1.0";
      last_updated = "";
      deployed_services = {};
      terraform_state = {
        containers = {};
        authentik_resources = {};
      };
      nixos_deployments = {};
    };

  # Write deployment state to a JSON file
  writeDeploymentState = stateFile: state:
    builtins.toFile "deployment-state.json" (builtins.toJSON state);

  # Get all services from manifest
  getAllServicesFromManifest = manifest:
    let
      coreServices = if manifest.core_services == null then {} else manifest.core_services;
      appServices = if manifest.services == null then {} else manifest.services;
    in
    coreServices // appServices;

  # Compare manifest with current deployment state
  compareManifestWithState = manifest: currentState:
    let
      manifestServices = getAllServicesFromManifest manifest;
      deployedServices = if currentState.deployed_services == null then {} else currentState.deployed_services;
      terraformContainers = if currentState.terraform_state == null || currentState.terraform_state.containers == null then {} else currentState.terraform_state.containers;
      authentikResources = if currentState.terraform_state == null || currentState.terraform_state.authentik_resources == null then {} else currentState.terraform_state.authentik_resources;
      nixosDeployments = if currentState.nixos_deployments == null then {} else currentState.nixos_deployments;

      # Find services that need to be deployed
      servicesToDeploy = builtins.filter (serviceName:
        let
          manifestService = manifestServices.${serviceName};
          deployedService = if builtins.hasAttr serviceName deployedServices then deployedServices.${serviceName} else null;
        in
        # Service needs deployment if:
        # 1. Not in deployed services, OR
        # 2. Manifest config changed (compare version/hash), OR
        # 3. Dependencies changed
        deployedService == null ||
        (if !builtins.hasAttr "version" manifestService || manifestService.version == null then "1.0" else manifestService.version) != (if deployedService == null || !builtins.hasAttr "version" deployedService || deployedService.version == null then "1.0" else deployedService.version) ||
        (compareDependencies (if builtins.hasAttr "depends_on" manifestService && manifestService.depends_on != null then manifestService.depends_on else []) (if builtins.hasAttr "depends_on" deployedService && deployedService.depends_on != null then deployedService.depends_on else []))
      ) (builtins.attrNames manifestServices);

      # Find containers that need to be created
      containersToCreate = builtins.filter (serviceName:
        let
          manifestService = manifestServices.${serviceName};
          deployedContainer = if builtins.hasAttr serviceName terraformContainers then terraformContainers.${serviceName} else {};
        in
        # Container needs creation if:
        # 1. Not in terraform state, OR
        # 2. VMID/IP changed, OR
        # 3. Resources changed significantly
        deployedContainer == {} ||
        (if builtins.hasAttr "ip" deployedContainer then deployedContainer.ip else "") != manifestService.ip ||
        (if builtins.hasAttr "vmid" deployedContainer then deployedContainer.vmid else 0) != manifestService.vmid
      ) (builtins.attrNames manifestServices);

      # Find OIDC apps that need to be created
      oidcAppsToCreate = builtins.filter (serviceName:
        let
          manifestService = manifestServices.${serviceName};
          deployedApp = if builtins.hasAttr serviceName authentikResources then authentikResources.${serviceName} else null;
        in
        # OIDC app needs creation if:
        # 1. Service has OIDC config AND
        # 2. Not in authentik resources OR
        # 3. OIDC config changed
        (if manifestService.interface == null || !builtins.hasAttr "auth" manifestService.interface || manifestService.interface.auth == null then null else manifestService.interface.auth) != null &&
        (if manifestService.interface == null || !builtins.hasAttr "auth" manifestService.interface || manifestService.interface.auth == null || !builtins.hasAttr "type" manifestService.interface.auth || manifestService.interface.auth.type == null then "" else manifestService.interface.auth.type) == "oidc" &&
        (deployedApp == null ||
         (if manifestService.interface.auth == null || !builtins.hasAttr "oidc" manifestService.interface.auth || manifestService.interface.auth.oidc == null || manifestService.interface.auth.oidc.client_id == null then "" else manifestService.interface.auth.oidc.client_id) != (if deployedApp == null || deployedApp.client_id == null then "" else deployedApp.client_id))
      ) servicesToDeploy;

      # Find services that need NixOS redeployment
      nixosRedeployments = builtins.filter (serviceName:
        let
          manifestService = manifestServices.${serviceName};
          deployedNixos = if builtins.hasAttr serviceName nixosDeployments then nixosDeployments.${serviceName} else null;
        in
        # NixOS redeployment needed if:
        # 1. Container was recreated, OR
        # 2. Service config changed, OR
        # 3. Secrets changed
        builtins.elem serviceName containersToCreate ||
        deployedNixos == null ||
        (if manifestService.version == null then "1.0" else manifestService.version) != (if deployedNixos.version == null then "1.0" else deployedNixos.version)
      ) servicesToDeploy;

    in {
      services_to_deploy = servicesToDeploy;
      containers_to_create = containersToCreate;
      oidc_apps_to_create = oidcAppsToCreate;
      nixos_redeployments = nixosRedeployments;

      # Summary stats
      summary = {
        total_services_in_manifest = builtins.length (builtins.attrNames manifestServices);
        services_already_deployed = builtins.length (builtins.attrNames deployedServices);
        services_needing_deployment = builtins.length servicesToDeploy;
        containers_needing_creation = builtins.length containersToCreate;
        oidc_apps_needing_creation = builtins.length oidcAppsToCreate;
        nixos_redeployments_needed = builtins.length nixosRedeployments;
      };
    };

  # Compare dependencies arrays
  compareDependencies = deps1: deps2:
    let
      deps1Sorted = builtins.sort builtins.lessThan (if deps1 == null then [] else deps1);
      deps2Sorted = builtins.sort builtins.lessThan (if deps2 == null then [] else deps2);
    in
    deps1Sorted != deps2Sorted;

  # Update deployment state after successful deployment
  updateDeploymentState = currentState: action: serviceName: manifestService:
    let
      timestamp = builtins.toString builtins.currentTime;
      updatedState = currentState // {
        last_updated = timestamp;
      };
    in
    if action == "service_deployed" then
      updatedState // {
        deployed_services = currentState.deployed_services // {
          ${serviceName} = {
            deployed_at = timestamp;
            version = if manifestService.version == null then "1.0" else manifestService.version;
            depends_on = if manifestService.depends_on == null then [] else manifestService.depends_on;
            ip = manifestService.ip;
            hostname = manifestService.hostname;
          };
        };
      }
    else if action == "container_created" then
      updatedState // {
        terraform_state = currentState.terraform_state // {
          containers = currentState.terraform_state.containers // {
            ${serviceName} = {
              created_at = timestamp;
              ip = manifestService.ip;
              vmid = manifestService.vmid;
              resources = manifestService.resources;
            };
          };
        };
      }
    else if action == "oidc_app_created" then
      updatedState // {
        terraform_state = currentState.terraform_state // {
          authentik_resources = currentState.terraform_state.authentik_resources // {
            ${serviceName} = {
              created_at = timestamp;
              client_id = if manifestService.interface.auth == null || !builtins.hasAttr "oidc" manifestService.interface.auth || manifestService.interface.auth.oidc == null || manifestService.interface.auth.oidc.client_id == null then "" else manifestService.interface.auth.oidc.client_id;
              client_type = if manifestService.interface.auth == null || !builtins.hasAttr "oidc" manifestService.interface.auth || manifestService.interface.auth.oidc == null || manifestService.interface.auth.oidc.client_type == null then "confidential" else manifestService.interface.auth.oidc.client_type;
            };
          };
        };
      }
    else if action == "nixos_deployed" then
      updatedState // {
        nixos_deployments = currentState.nixos_deployments // {
          ${serviceName} = {
            deployed_at = timestamp;
            version = if manifestService.version == null then "1.0" else manifestService.version;
          };
        };
      }
    else
      currentState;

  # Generate deployment plan
  generateDeploymentPlan = manifest: currentState:
    let
      comparison = compareManifestWithState manifest currentState;
    in {
      inherit (comparison) summary;

      phases = {
        infrastructure = {
          description = "Create missing containers and infrastructure";
          actions = map (serviceName: {
            type = "create_container";
            service = serviceName;
            ip = manifest.services.${serviceName}.ip;
            vmid = manifest.services.${serviceName}.vmid;
          }) comparison.containers_to_create;
        };

        authentik = {
          description = "Create missing OIDC applications and providers";
          actions = map (serviceName: {
            type = "create_oidc_app";
            service = serviceName;
            client_id = manifest.services.${serviceName}.interface.auth.oidc.client_id;
            redirect_uris = manifest.services.${serviceName}.interface.auth.oidc.redirect_uris;
          }) comparison.oidc_apps_to_create;
        };

        nixos = {
          description = "Deploy NixOS configurations for services";
          actions = map (serviceName: {
            type = "deploy_nixos";
            service = serviceName;
            ip = manifest.services.${serviceName}.ip;
          }) comparison.nixos_redeployments;
        };
      };

      # Execution order considering dependencies
      execution_order = generateExecutionOrder manifest comparison.services_to_deploy;
    };

  # Generate execution order considering dependencies
  generateExecutionOrder = manifest: servicesToDeploy:
    let
      # Create dependency graph
      dependencyGraph = builtins.listToAttrs (map (serviceName: {
        name = serviceName;
        value = if builtins.hasAttr serviceName manifest.services && manifest.services.${serviceName}.depends_on != null then manifest.services.${serviceName}.depends_on else [];
      }) servicesToDeploy);

      # Topological sort (simplified)
      sorted = topologicalSort dependencyGraph servicesToDeploy;
    in
    sorted;

  # Simple topological sort
  topologicalSort = graph: nodes:
    if nodes == [] then []
    else
      let
        # Find nodes with no dependencies
        noDeps = builtins.filter (node:
          let deps = if builtins.hasAttr node graph then graph.${node} else []; in
          builtins.all (dep: !builtins.elem dep nodes) deps
        ) nodes;

        # Remove processed nodes
        remaining = builtins.filter (node: !builtins.elem node noDeps) nodes;
      in
      if noDeps == [] then
        # Circular dependency detected
        throw "Circular dependency detected in services"
      else
        noDeps ++ (topologicalSort graph remaining);

  # Validate deployment plan
  validateDeploymentPlan = plan: manifest:
    let
      # Check for circular dependencies
      checkCircularDeps = serviceList:
        let
          hasCircular = serviceName:
            let
              deps = if builtins.hasAttr serviceName manifest.services && manifest.services.${serviceName}.depends_on != null then manifest.services.${serviceName}.depends_on else [];
              visited = [serviceName];
            in
            checkDeps deps visited;

          checkDeps = deps: visited:
            if deps == [] then false
            else
              let
                dep = builtins.head deps;
                rest = builtins.tail deps;
              in
              if builtins.elem dep visited then
                true  # Circular dependency
              else
                checkDeps rest visited ||
                ((if builtins.hasAttr dep manifest.services && manifest.services.${dep}.depends_on != null then manifest.services.${dep}.depends_on else []) != [] &&
                 checkDeps (if builtins.hasAttr dep manifest.services && manifest.services.${dep}.depends_on != null then manifest.services.${dep}.depends_on else []) (visited ++ [dep]));
        in
        builtins.any hasCircular serviceList;

      # Check for missing dependencies
      checkMissingDeps = serviceList:
        builtins.any (serviceName:
          let deps = if builtins.hasAttr serviceName manifest.services && manifest.services.${serviceName}.depends_on != null then manifest.services.${serviceName}.depends_on else []; in
          builtins.any (dep: !builtins.elem dep serviceList && !builtins.hasAttr dep manifest.core_services) deps
        ) serviceList;
    in
    if checkCircularDeps plan.execution_order then
      throw "Deployment plan has circular dependencies"
    else if checkMissingDeps plan.execution_order then
      throw "Deployment plan has missing dependencies"
    else
      plan;

in {
  inherit
    readDeploymentState
    writeDeploymentState
    compareManifestWithState
    updateDeploymentState
    generateDeploymentPlan
    validateDeploymentPlan;
}
