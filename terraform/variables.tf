variable "username_prefix" {
  description = "Prefix for the username"
  type        = string
  default = ""
}

variable "user_count" {
  description = "Number of users to create"
  type        = string
  default = "0"
}
variable "user_start" {
  description = "Starting index for user numbering"
  type        = string
  default = "0"
}

variable "rg-suffix" {
  description = "Suffix for the resource group name"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure location for resources"
  type        = string
  default     = ""
}

variable "password" {
  description = "Password for the admin user"
  type        = string
  default     = ""
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = ""
}