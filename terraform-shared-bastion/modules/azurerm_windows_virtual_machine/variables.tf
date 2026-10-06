variable "resource_group_name" {
  description = "Resource group name for VM and Bastion resources."
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment."
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for virtual network."
  type        = list(string)
}

variable "vm_subnet_name" {
  description = "Subnet name for Windows VM."
  type        = string
}

variable "vm_subnet_cidr" {
  description = "CIDR for Windows VM subnet."
  type        = string
}

variable "subscription_id" {
  type = string
}

variable "windows_vm_name" {
  description = "Windows virtual machine name."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
}

variable "username" {
  description = "Admin username for Windows VM."
  type        = string
}

variable "password" {
  description = "Admin password for Windows VM."
  type        = string
}

variable "environment" {
  type = string

}

variable "bastion_host_id" {
  description = "bastion host resource ID."
  type        = string
}

variable "bastion_host_resource_group_name" {
  description = "bastion host resource group name."
  type        = string
}

variable "bastion_host_virtual_network_name" {
  description = "bastion host virtual network name."
  type        = string
}
variable "bastion_host_virtual_network_id" {
  description = "bastion host virtual network id."
  type        = string
}

variable "user_principal_domain" {
  description = "User principal domain for the Azure AD tenant."
  type        = string
}

variable "onedrive_license_group_object_id" {
  description = "Object ID of the OneDrive license group."
  type        = string
}
