output "radius_provider_id" {
  value       = authentik_provider_radius.radius.id
  description = "RADIUS provider ID"
}

output "radius_application_id" {
  value       = authentik_application.radius.id
  description = "RADIUS application ID"
}

output "radius_outpost_id" {
  value       = authentik_outpost.radius.id
  description = "RADIUS outpost ID"
}

output "radius_metrics_port" {
  value       = var.radius_metrics_port
  description = "Metrics port for RADIUS outpost"
}




