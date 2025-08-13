output "vaultwarden_provider_id" {
  value = authentik_provider_oauth2.vaultwarden.id
}

output "vaultwarden_application_id" {
  value = authentik_application.vaultwarden.id
}

