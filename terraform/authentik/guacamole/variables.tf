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

variable "guac_provider_name" {
  description = "Name for the Guacamole OAuth2 provider"
  type        = string
  default     = "Guacamole Provider"
}

variable "guac_client_id" {
  description = "Guacamole OAuth2 client ID"
  type        = string
}

## Public client, no secret needed

variable "guac_redirect_uri" {
  description = "Redirect URI for Guacamole (e.g., https://guac.nixmox.lan/)"
  type        = string
}

variable "guac_app_name" {
  description = "Authentik application name for Guacamole"
  type        = string
  default     = "Guacamole"
}

variable "guac_app_slug" {
  description = "Authentik application slug for Guacamole"
  type        = string
  default     = "guacamole"
}

variable "guac_app_group" {
  description = "Group label for Guacamole app in the Authentik UI"
  type        = string
  default     = "Remote Access"
}

variable "guac_launch_url" {
  description = "Launch URL for Guacamole"
  type        = string
}


