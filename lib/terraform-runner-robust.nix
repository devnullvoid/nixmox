# Robust Terraform execution and management
# Handles Terraform init, plan, apply, and output management with better error handling

{ lib, pkgs, config, ... }:

let
  # Terraform runner configuration
  terraformRunnerConfig = {
    terraform_version = lib.mkOption {
      type = lib.types.str;
      default = "1.5.0";
      description = "Terraform version to use";
    };
    
    workspace_prefix = lib.mkOption {
      type = lib.types.str;
      default = "nixmox";
      description = "Prefix for Terraform workspaces";
    };
    
    state_backend = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Terraform state backend configuration";
    };
    
    variables_file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to variables file";
    };
  };

  # Generate Terraform workspace name
  generateWorkspaceName = phase: serviceName: let
    prefix = "nixmox";
  in
    if serviceName != null then
      "${prefix}-${phase}-${serviceName}"
    else
      "${prefix}-${phase}";

  # Safely get attribute value with fallback
  safeGetAttr = attr: obj: fallback:
    if obj != null && lib.hasAttr attr obj then
      obj.${attr}
    else
      fallback;

  # Generate Terraform variables from manifest
  generateTerraformVariables = manifest: service: let
    # Extract variables from service interface
    terraformVars = if service.interface != null && service.interface.terraform != null then
      safeGetAttr "variables" service.interface.terraform {}
    else {};
    
    # Add common variables
    commonVars = {
      service_name = safeGetAttr "name" service "unknown";
      service_ip = safeGetAttr "ip" service "0.0.0.0";
      service_hostname = safeGetAttr "hostname" service "localhost";
      network_cidr = safeGetAttr "network_cidr" manifest.network "192.168.0.0/24";
      gateway = safeGetAttr "gateway" manifest.network "192.168.0.1";
      dns_server = safeGetAttr "dns_server" manifest.network "192.168.0.1";
    };
    
    # Add proxy variables if configured
    proxyVars = if service.interface != null && lib.hasAttr "proxy" service.interface && service.interface.proxy != null then {
      domain = safeGetAttr "domain" service.interface.proxy "localhost";
      path = safeGetAttr "path" service.interface.proxy "/";
      upstream = safeGetAttr "upstream" service.interface.proxy "localhost:8080";
    } else {};
    
    # Add auth variables if configured
    authVars = if service.interface != null && lib.hasAttr "auth" service.interface && service.interface.auth != null && lib.hasAttr "oidc" service.interface.auth && service.interface.auth.oidc != null then {
      oidc_client_id = safeGetAttr "client_id" service.interface.auth.oidc "auto";
      oidc_redirect_uris = safeGetAttr "redirect_uris" service.interface.auth.oidc [];
      oidc_scopes = safeGetAttr "scopes" service.interface.auth.oidc ["openid" "email"];
      oidc_username_claim = safeGetAttr "username_claim" service.interface.auth.oidc "preferred_username";
      oidc_groups_claim = safeGetAttr "groups_claim" service.interface.auth.oidc "groups";
    } else {};
    
    # Add database variables if configured
    dbVars = if service.interface != null && lib.hasAttr "db" service.interface && service.interface.db != null then {
      db_name = safeGetAttr "database" service.interface.db null;
      db_role = safeGetAttr "role" service.interface.db null;
      db_mode = safeGetAttr "mode" service.interface.db null;
    } else {};
  in
    commonVars // proxyVars // authVars // dbVars // terraformVars;

  # Generate Terraform variables file
  generateTerraformVariablesFile = manifest: service: let
    variables = generateTerraformVariables manifest service;
    variablesContent = lib.concatStringsSep "\n" (lib.mapAttrs (name: value: 
      "${name} = ${if lib.isString value then "\"${value}\"" else if lib.isList value then "[${lib.concatStringsSep ", " (lib.map (v: if lib.isString v then "\"${v}\"" else toString v) value)}]" else toString value}"
    ) variables);
    serviceName = safeGetAttr "name" service "unknown";
  in
    pkgs.writeText "terraform-variables-${serviceName}.tfvars" variablesContent;

  # Get Terraform directory for a service
  getTerraformDir = serviceName: phase: let
    # Default to current directory if config is not available
    defaultDir = ".";
    
    # Try to get service config from config if available
    serviceConfig = if config != null && lib.hasAttr "services" config && lib.hasAttr "nixmox" config.services then
      if serviceName != null then
        config.services.nixmox.services.${serviceName} or null
      else
        config.services.nixmox.core_services.${phase} or null
    else
      null;
    
    terraformConfig = if serviceConfig != null && serviceConfig.interface != null && serviceConfig.interface.terraform != null then
      safeGetAttr "modules" serviceConfig.interface.terraform []
    else [];
  in
    if lib.length terraformConfig > 0 then
      lib.head terraformConfig
    else
      defaultDir;

  # Generate Terraform initialization script
  generateTerraformInitScript = phase: serviceName: workspaceName: let
    terraformDir = getTerraformDir serviceName phase;
    
    initScript = pkgs.writeShellScript "terraform-init-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Initializing Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${terraformDir}
      
      # Initialize Terraform
      echo "Running terraform init..."
      terraform init
      
      # Create and switch to workspace
      echo "Creating/selecting workspace: $WORKSPACE"
      terraform workspace new $WORKSPACE 2>/dev/null || terraform workspace select $WORKSPACE
      
      echo "Terraform initialization completed for $WORKSPACE"
    '';
  in
    initScript;

  # Generate Terraform plan script
  generateTerraformPlanScript = phase: serviceName: workspaceName: variablesFile: let
    terraformDir = getTerraformDir serviceName phase;
    
    planScript = pkgs.writeShellScript "terraform-plan-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      VARIABLES_FILE="${variablesFile}"
      
      echo "Planning Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${terraformDir}
      
      # Select workspace
      terraform workspace select $WORKSPACE
      
      # Generate variables file if not provided
      if [ ! -f "$VARIABLES_FILE" ]; then
        echo "Generating variables file..."
        cat > terraform.tfvars << 'EOF'
        ${if variablesFile != null then variablesFile else ""}
      EOF
      fi
      
      # Run terraform plan
      echo "Running terraform plan..."
      terraform plan -var-file="$VARIABLES_FILE" -out=tfplan
      
      echo "Terraform plan completed for $WORKSPACE"
    '';
  in
    planScript;

  # Generate Terraform apply script
  generateTerraformApplyScript = phase: serviceName: workspaceName: let
    terraformDir = getTerraformDir serviceName phase;
    
    applyScript = pkgs.writeShellScript "terraform-apply-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Applying Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${terraformDir}
      
      # Select workspace
      terraform workspace select $WORKSPACE
      
      # Check if plan exists
      if [ ! -f "tfplan" ]; then
        echo "Error: No terraform plan found. Run plan first."
        exit 1
      fi
      
      # Run terraform apply
      echo "Running terraform apply..."
      terraform apply tfplan
      
      # Clean up plan file
      rm -f tfplan
      
      echo "Terraform apply completed for $WORKSPACE"
    '';
  in
    applyScript;

  # Generate Terraform output extraction script
  generateTerraformOutputScript = phase: serviceName: workspaceName: outputs: let
    terraformDir = getTerraformDir serviceName phase;
    
    outputScript = pkgs.writeShellScript "terraform-output-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Extracting Terraform outputs for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${terraformDir}
      
      # Select workspace
      terraform workspace select $WORKSPACE
      
      # Extract outputs
      ${lib.concatStringsSep "\n" (lib.mapAttrs (name: description: ''
        echo "Extracting output: ${name}"
        OUTPUT_VALUE=$(terraform output -raw ${name})
        echo "${name}=\$OUTPUT_VALUE" >> /tmp/nixmox-terraform-outputs
        echo "${name}: \$OUTPUT_VALUE"
      '') outputs)}
      
      echo "Terraform outputs extracted for $WORKSPACE"
    '';
  in
    outputScript;

  # Check if Terraform changes are needed
  checkTerraformChanges = phase: serviceName: workspaceName: let
    terraformDir = getTerraformDir serviceName phase;
    
    checkScript = pkgs.writeShellScript "terraform-check-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Checking Terraform changes for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${terraformDir}
      
      # Select workspace
      terraform workspace select $WORKSPACE
      
      # Run terraform plan with -refresh-only to check for changes
      echo "Running terraform plan -refresh-only..."
      if terraform plan -refresh-only -detailed-exitcode > /dev/null 2>&1; then
        echo "No Terraform changes needed for $WORKSPACE"
        exit 0
      else
        echo "Terraform changes detected for $WORKSPACE"
        exit 1
      fi
    '';
  in
    checkScript;

in {
  inherit terraformRunnerConfig;
  inherit generateWorkspaceName;
  inherit generateTerraformVariables;
  inherit generateTerraformVariablesFile;
  inherit generateTerraformInitScript;
  inherit generateTerraformPlanScript;
  inherit generateTerraformApplyScript;
  inherit generateTerraformOutputScript;
  inherit checkTerraformChanges;
}