variable "subscription_id" {
  description = "Azure subscription ID where resources are created."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID used for AzureAD resources."
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment."
  type        = string
  default     = "eastus"
}

variable "username" {
  description = "username"
  type        = string
}

variable "password" {
  description = "password"
  type        = string
  default     = ""
}

variable "env_count" {
  description = "Number of environments to create"
  type        = string
}
variable "env_start" {
  description = "Starting index for environment numbering"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "user_principal_domain" {
  description = "User principal domain for the Azure AD tenant."
  type        = string
}

variable "onedrive_license_group_object_id" {
  description = "Object ID of the OneDrive license group."
  type        = string
}
