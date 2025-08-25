# Simple Terraform execution and management
# Basic version without complex attribute handling

{ lib, pkgs, config, ... }:

let
  # Generate Terraform workspace name
  generateWorkspaceName = phase: serviceName: let
    prefix = "nixmox";
  in
    if serviceName != null then
      "${prefix}-${phase}-${serviceName}"
    else
      "${prefix}-${phase}";

  # Generate Terraform variables from manifest
  generateTerraformVariables = manifest: service: let
    # Extract variables from service interface
    terraformVars = if service.interface != null && service.interface.terraform != null then
      service.interface.terraform.variables or {}
    else {};
    
    # Add common variables
    commonVars = {
      service_name = service.name or "unknown";
      service_ip = service.ip or "0.0.0.0";
      service_hostname = service.hostname or "localhost";
      network_cidr = manifest.network.network_cidr or "192.168.0.0/24";
      gateway = manifest.network.gateway or "192.168.0.1";
      dns_server = manifest.network.dns_server or "192.168.0.1";
    };
  in
    commonVars // terraformVars;

  # Generate Terraform variables file
  generateTerraformVariablesFile = manifest: service: let
    variables = generateTerraformVariables manifest service;
    variablesContent = lib.concatStringsSep "\n" (lib.mapAttrs (name: value: 
      "${name} = \"${toString value}\""
    ) variables);
    serviceName = service.name or "unknown";
  in
    pkgs.writeText "terraform-variables-${serviceName}.tfvars" variablesContent;

  # Generate Terraform initialization script
  generateTerraformInitScript = phase: serviceName: workspaceName: let
    initScript = pkgs.writeShellScript "terraform-init-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Initializing Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd .
      
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
    planScript = pkgs.writeShellScript "terraform-plan-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      VARIABLES_FILE="${variablesFile}"
      
      echo "Planning Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd .
      
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
    applyScript = pkgs.writeShellScript "terraform-apply-${phase}-${if serviceName != null then serviceName else "core"}" ''
      set -euo pipefail
      
      PHASE="${phase}"
      SERVICE_NAME="${if serviceName != null then serviceName else "core"}"
      WORKSPACE="${workspaceName}"
      
      echo "Applying Terraform for $PHASE phase, service: $SERVICE_NAME"
      
      # Change to Terraform directory
      cd .
      
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

in {
  inherit generateWorkspaceName;
  inherit generateTerraformVariables;
  inherit generateTerraformVariablesFile;
  inherit generateTerraformInitScript;
  inherit generateTerraformPlanScript;
  inherit generateTerraformApplyScript;
}