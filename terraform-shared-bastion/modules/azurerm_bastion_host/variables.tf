variable "resource_group_name" {
  description = "Resource group name for Bastion resources."
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment."
  type        = string
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for virtual network."
  type        = list(string)
}

variable "bastion_subnet_cidr" {
  description = "CIDR for AzureBastionSubnet."
  type        = string
}

variable "bastion_name" {
  description = "Azure Bastion host name."
  type        = string
}

variable "bastion_public_ip_name" {
  description = "Public IP name for Bastion."
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
}
