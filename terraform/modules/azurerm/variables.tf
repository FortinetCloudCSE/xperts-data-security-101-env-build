variable "username" {
  description = "Username for the VM user"
  type        = string
}

variable "password" {
  description = "Password for the VM user"
  type        = string
}

variable "rg-suffix" {
  description = "The suffix to use for all resource group names"
  type        = string
}

variable "location" {
  description = "The Azure region to deploy resources in"
  type        = string
}