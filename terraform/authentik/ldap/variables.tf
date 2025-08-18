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

variable "ldap_provider_name" {
  description = "Name for the LDAP provider"
  type        = string
  default     = "LDAP Provider"
}

variable "ldap_base_dn" {
  description = "Base DN served by LDAP (e.g., dc=nixmox,dc=lan)"
  type        = string
}

variable "ldap_bind_mode" {
  description = "LDAP bind mode (direct or static)"
  type        = string
  default     = "direct"
}

variable "ldap_search_mode" {
  description = "LDAP search mode (direct or default)"
  type        = string
  default     = "direct"
}

variable "ldap_mfa_support" {
  description = "Enable MFA support for LDAP"
  type        = bool
  default     = true
}

variable "ldap_uid_start_number" {
  description = "UID start number for LDAP entries"
  type        = number
  default     = 2000
}

variable "ldap_gid_start_number" {
  description = "GID start number for LDAP entries"
  type        = number
  default     = 4000
}

variable "ldap_app_name" {
  description = "Application name for LDAP Directory"
  type        = string
  default     = "LDAP Directory"
}

variable "ldap_app_slug" {
  description = "Application slug for LDAP Directory"
  type        = string
  default     = "ldap-directory"
}

variable "ldap_outpost_name" {
  description = "Outpost name for LDAP"
  type        = string
  default     = "LDAP Outpost"
}

variable "ldap_metrics_port" {
  description = "Metrics port for LDAP outpost (default: 9300)"
  type        = number
  default     = 9300
}




