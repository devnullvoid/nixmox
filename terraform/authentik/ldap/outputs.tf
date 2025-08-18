output "ldap_provider_id" {
  value       = authentik_provider_ldap.ldap.id
  description = "LDAP provider ID"
}

output "ldap_application_id" {
  value       = authentik_application.ldap.id
  description = "LDAP application ID"
}

output "ldap_outpost_id" {
  value       = authentik_outpost.ldap.id
  description = "LDAP outpost ID"
}

output "ldap_metrics_port" {
  value       = var.ldap_metrics_port
  description = "Metrics port for LDAP outpost"
}




