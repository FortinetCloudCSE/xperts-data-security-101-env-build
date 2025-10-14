variable "username_prefix" {
  description = "Prefix for the username"
  type        = string
}

variable "user_count" {
  description = "Number of users to create"
  type        = string
}
variable "user_start" {
  description = "Starting index for user numbering"
  type        = string
}

variable "rg-suffix" {
  description = "Suffix for the resource group name"
  type        = string
}

variable "location" {
  description = "Azure location for resources"
  type        = string
}

variable "password" {
  description = "Password for the admin user"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}