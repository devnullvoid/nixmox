variable "authentik_url" {
  description = "Authentik URL (e.g., https://auth.nixmox.lan)"
  type        = string
}

variable "authentik_token" {
  description = "Authentik automation API token"
  type        = string
  sensitive   = true
}

variable "authentik_insecure" {
  description = "Allow insecure TLS (self-signed)"
  type        = bool
  default     = true
}

variable "radius_provider_name" {
  description = "Name for the RADIUS provider"
  type        = string
  default     = "RADIUS Provider"
}

variable "radius_shared_secret" {
  description = "Shared secret for RADIUS"
  type        = string
  sensitive   = true
}

variable "radius_client_networks" {
  description = "Comma-separated CIDRs allowed to use the RADIUS provider"
  type        = string
  default     = "0.0.0.0/0, ::/0"
}

variable "radius_mfa_support" {
  description = "Enable MFA support for RADIUS"
  type        = bool
  default     = true
}

variable "radius_app_name" {
  description = "Application name for RADIUS access"
  type        = string
  default     = "RADIUS Access"
}

variable "radius_app_slug" {
  description = "Application slug for RADIUS access"
  type        = string
  default     = "radius-access"
}

variable "radius_outpost_name" {
  description = "Outpost name for RADIUS"
  type        = string
  default     = "RADIUS Outpost"
}

variable "radius_metrics_port" {
  description = "Metrics port for RADIUS outpost (default: 9301)"
  type        = number
  default     = 9301
}




