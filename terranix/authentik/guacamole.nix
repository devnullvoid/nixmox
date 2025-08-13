{ lib, ... }:
{
  terraform = {
    required_version = ">= 1.5.0";
    required_providers.authentik = {
      source = "goauthentik/authentik";
      version = ">= 2024.6.0";
    };
  };

  provider.authentik = {
    url = "${var.authentik_url}";
    token = "${var.authentik_token}";
    insecure = var.authentik_insecure;
  };

  variable = {
    authentik_url = { type = "string"; description = "Authentik base URL"; };
    authentik_token = { type = "string"; sensitive = true; description = "Authentik API token"; };
    authentik_insecure = { type = "bool"; default = true; description = "Allow self-signed TLS"; };

    guac_client_id = { type = "string"; description = "Guacamole OIDC client ID"; };
    guac_client_secret = { type = "string"; sensitive = true; description = "Guacamole OIDC client secret"; };
    guac_redirect_uri = { type = "string"; description = "Guacamole redirect URI (e.g., https://guac.nixmox.lan/)"; };
    guac_launch_url = { type = "string"; description = "Guacamole launch URL"; };
    guac_provider_name = { type = "string"; default = "Guacamole Provider"; };
    guac_app_name = { type = "string"; default = "Guacamole"; };
    guac_app_slug = { type = "string"; default = "guacamole"; };
    guac_app_group = { type = "string"; default = "Remote Access"; };
  };

  data = {
    authentik_flow = {
      default_authentication = { slug = "default-authentication-flow"; };
      default_invalidation = { slug = "default-invalidation-flow"; };
      provider_authorize_implicit = { slug = "default-provider-authorization-implicit-consent"; };
    };

    authentik_property_mapping_provider_scope = {
      scope_openid = { managed = "goauthentik.io/providers/oauth2/scope-openid"; };
      scope_email = { managed = "goauthentik.io/providers/oauth2/scope-email"; };
      scope_profile = { managed = "goauthentik.io/providers/oauth2/scope-profile"; };
    };
  };

  resource = {
    authentik_oauth2_provider.guacamole = {
      name = var.guac_provider_name;
      client_id = var.guac_client_id;
      client_secret = var.guac_client_secret;
      authorization_flow = data.authentik_flow.provider_authorize_implicit.id;
      invalidation_flow = data.authentik_flow.default_invalidation.id;
      client_type = "confidential";

      allowed_redirect_uris = [ var.guac_redirect_uri ];

      property_mappings = [
        data.authentik_property_mapping_provider_scope.scope_openid.id,
        data.authentik_property_mapping_provider_scope.scope_email.id,
        data.authentik_property_mapping_provider_scope.scope_profile.id,
      ];
    };

    authentik_application.guacamole = {
      name = var.guac_app_name;
      slug = var.guac_app_slug;
      provider = lib.terraformRef "authentik_oauth2_provider.guacamole.id";
      group = var.guac_app_group;
      launch_url = var.guac_launch_url;
      meta_launch_url = var.guac_launch_url;
      meta_icon = "mdi:remote-desktop";
      meta_publisher = "NixMox";
      open_in_new_tab = false;
      disable_everyone = false;
    };
  };

  output = {
    guacamole_provider_id = {
      description = "ID of the Authentik OAuth2 provider for Guacamole";
      value = lib.terraformRef "authentik_oauth2_provider.guacamole.id";
    };
    guacamole_application_id = {
      description = "ID of the Authentik Application for Guacamole";
      value = lib.terraformRef "authentik_application.guacamole.id";
    };
  };
}


