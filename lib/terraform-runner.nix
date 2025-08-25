# Terraform execution and management
# Handles Terraform init, plan, apply, and output management

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
    prefix = config.services.nixmox.terraform.workspace_prefix or "nixmox";
  in
    if serviceName != null then
      "${prefix}-${phase}-${serviceName}"
    else
      "${prefix}-${phase}";

  # Generate Terraform variables from manifest
  generateTerraformVariables = manifest: service: let
    # Extract variables from service interface
    terraformVars = service.interface.terraform.variables or {};
    
    # Add common variables
    commonVars = {
      service_name = service.name;
      service_ip = service.ip;
      service_hostname = service.hostname;
      network_cidr = manifest.network.network_cidr;
      gateway = manifest.network.gateway;
      dns_server = manifest.network.dns_server;
    };
    
    # Add proxy variables if configured
    proxyVars = if service.interface.proxy != null then {
      domain = service.interface.proxy.domain;
      path = service.interface.proxy.path;
      upstream = service.interface.proxy.upstream;
    } else {};
    
    # Add auth variables if configured
    authVars = if service.interface.auth != null && service.interface.auth.oidc != null then {
      oidc_client_id = service.interface.auth.oidc.client_id or "auto";
      oidc_redirect_uris = service.interface.auth.oidc.redirect_uris;
      oidc_scopes = service.interface.auth.oidc.scopes;
      oidc_username_claim = service.interface.auth.oidc.username_claim;
      oidc_groups_claim = service.interface.auth.oidc.groups_claim;
    } else {};
    
    # Add database variables if configured
    dbVars = if service.interface.db != null then {
      db_name = service.interface.db.database;
      db_role = service.interface.db.role;
      db_mode = service.interface.db.mode;
    } else {};
  in
    commonVars // proxyVars // authVars // dbVars // terraformVars;

  # Generate Terraform variables file
  generateTerraformVariablesFile = manifest: service: let
    variables = generateTerraformVariables manifest service;
    variablesContent = lib.concatStringsSep "\n" (lib.mapAttrs (name: value: 
      "${name} = ${lib.generators.toPlist {} value}"
    ) variables);
  in
    pkgs.writeText "terraform-variables-${service.name}.tfvars" variablesContent;

  # Generate Terraform initialization script
  generateTerraformInitScript = phase: serviceName: workspaceName: let
    terraformDir = if serviceName != null then
      config.services.nixmox.services.${serviceName}.interface.terraform.modules or []
    else
      config.services.nixmox.core_services.${phase}.interface.terraform.modules or [];
    
    initScript = pkgs.writeShellScript "terraform-init-${phase}-${serviceName or "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${serviceName or "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Initializing Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${lib.head terraformDir}
      
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
    planScript = pkgs.writeShellScript "terraform-plan-${phase}-${serviceName or "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${serviceName or "core"}"
      WORKSPACE="${workspaceName}"
      VARIABLES_FILE="${variablesFile}"
      
      echo "Planning Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${lib.head (if serviceName != null then
        config.services.nixmox.services.${serviceName}.interface.terraform.modules or []
      else
        config.services.nixmox.core_services.${phase}.interface.terraform.modules or [])}
      
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
    applyScript = pkgs.writeShellScript "terraform-apply-${phase}-${serviceName or "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${serviceName or "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Applying Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${lib.head (if serviceName != null then
        config.services.nixmox.services.${serviceName}.interface.terraform.modules or []
      else
        config.services.nixmox.core_services.${phase}.interface.terraform.modules or [])}
      
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
    outputScript = pkgs.writeShellScript "terraform-output-${phase}-${serviceName or "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${serviceName or "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Extracting Terraform outputs for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${lib.head (if serviceName != null then
        config.services.nixmox.services.${serviceName}.interface.terraform.modules or []
      else
        config.services.nixmox.core_services.${phase}.interface.terraform.modules or [])}
      
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
    checkScript = pkgs.writeShellScript "terraform-check-${phase}-${serviceName or "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${serviceName or "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Checking Terraform changes for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd ${lib.head (if serviceName != null then
        config.services.nixmox.services.${serviceName}.interface.terraform.modules or []
      else
        config.services.nixmox.core_services.${phase}.interface.terraform.modules or [])}
      
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