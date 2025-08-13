variable "authentik_url" {
  description = "Base URL of the Authentik instance (e.g., https://auth.nixmox.lan)"
  type        = string
}

variable "authentik_token" {
  description = "API token for Authentik"
  type        = string
  sensitive   = true
}

variable "authentik_insecure" {
  description = "Disable TLS verification for Authentik provider"
  type        = bool
  default     = false
}

variable "vw_client_id" {
  description = "Vaultwarden OIDC client ID"
  type        = string
}

variable "vw_client_secret" {
  description = "Vaultwarden OIDC client secret"
  type        = string
  sensitive   = true
}

variable "vw_redirect_uri" {
  description = "Vaultwarden OIDC redirect URI"
  type        = string
  default     = "https://vault.nixmox.lan/oidc/callback"
}

variable "vw_launch_url" {
  description = "Vaultwarden application launch URL"
  type        = string
  default     = "https://vault.nixmox.lan"
}

