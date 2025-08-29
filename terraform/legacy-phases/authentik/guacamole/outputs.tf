output "guacamole_provider_id" {
  description = "ID of the Authentik OAuth2 provider for Guacamole"
  value       = authentik_provider_oauth2.guacamole.id
}

output "guacamole_application_id" {
  description = "ID of the Authentik Application for Guacamole"
  value       = authentik_application.guacamole.id
}


