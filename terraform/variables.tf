variable "username_prefix" {
  description = "Prefix for the username"
  type        = string
}

variable "user_count" {
  description = "Number of users to create"
  type        = number
}
variable "user_start" {
  description = "Starting index for user numbering"
  type        = number
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
