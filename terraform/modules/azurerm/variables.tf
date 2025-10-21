variable "username" {
  description = "Username for the VM user"
  type        = string
}

variable "password" {
  description = "Password for the VM user"
  type        = string
}

variable "rg_suffix" {
  description = "The suffix to use for all resource group names"
  type        = string
}

variable "location" {
  description = "The Azure region to deploy resources in"
  type        = string
}

variable "user_principal_domain" {
  description = "The domain name for the Azure AD tenant"
  type        = string
  default     = ""
}

variable "onedrive_license_group_object_id" {
  description = "The Entra ID object id of the group for OneDrive licenses"
  type        = string
  default     = ""
}