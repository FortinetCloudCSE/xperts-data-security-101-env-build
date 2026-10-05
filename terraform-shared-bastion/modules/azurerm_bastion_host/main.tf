resource "azurerm_resource_group" "resource_group" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
  lifecycle {
    ignore_changes = [
      tags["CreatedOnDate"]
    ]
  }
}

resource "azurerm_virtual_network" "virtual_network" {
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  name          = var.vnet_name
  address_space = var.vnet_address_space
  tags          = var.tags
}

resource "azurerm_subnet" "bastion_subnet" {
  resource_group_name = azurerm_resource_group.resource_group.name

  virtual_network_name = azurerm_virtual_network.virtual_network.name
  name                 = "AzureBastionSubnet"
  address_prefixes     = [var.bastion_subnet_cidr]
}

resource "azurerm_public_ip" "public_ip" {
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  name              = var.bastion_public_ip_name
  allocation_method = "Static"
  sku               = "Standard"
  zones             = ["1", "2", "3"]
  tags              = var.tags
}

resource "azurerm_bastion_host" "bastion_host" {
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  sku                    = "Standard"
  copy_paste_enabled     = true
  file_copy_enabled      = true
  ip_connect_enabled     = true
  shareable_link_enabled = true

  scale_units = 3

  name = var.bastion_name
  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
  tags = var.tags
}

output "resource_group" {
  value = azurerm_resource_group.resource_group
}

output "virtual_network" {
  value = azurerm_virtual_network.virtual_network
}

output "bastion_host" {
  value = azurerm_bastion_host.bastion_host
}