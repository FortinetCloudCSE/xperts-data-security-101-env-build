locals {
  env_count = tonumber(var.env_count)
  env_start = tonumber(var.env_start)

  location = var.location
  password = var.password
  username = var.username

  tags = var.tags

  environments = {
    for i in range(local.env_start, local.env_start + local.env_count) :
    format("%s%02s", local.username, i) => {
      username           = format("%s%02s", local.username, i)
      vnet_address_space = "172.16.${i}.0"
    }
  }

  bastion_hosts = {
    bastion_host = {
      resource_group_name = "rg-xperts-dlp101-bastion"
      location            = local.location
      name                = "bastion-dlp101"
      vnet_name           = "vnet-dlp101-bastion"
      vnet_address_space  = ["10.10.0.0/16"]
      bastion_subnet_cidr = "10.10.10.0/24"
      public_ip_name      = "bastion-dlp101-pip"
      tags                = local.tags
    }
  }
}


module "module_bastion_host" {
  source = "./modules/azurerm_bastion_host"

  for_each = local.bastion_hosts

  resource_group_name = each.value.resource_group_name
  location            = each.value.location

  vnet_name              = each.value.vnet_name
  vnet_address_space     = each.value.vnet_address_space
  bastion_subnet_cidr    = each.value.bastion_subnet_cidr
  bastion_name           = each.value.name
  bastion_public_ip_name = each.value.public_ip_name
  tags                   = each.value.tags
}

output "module_bastion_host" {
  value = module.module_bastion_host
}

module "module_windows_virtual_machine" {
  for_each = local.environments

  source = "./modules/azurerm_windows_virtual_machine"

  resource_group_name = "rg-xperts-dlp101-${each.value.username}"
  location            = local.location
  tags                = local.tags

  onedrive_license_group_object_id = var.onedrive_license_group_object_id
  user_principal_domain            = var.user_principal_domain

  vnet_name          = "vnet-dlp101"
  vnet_address_space = ["${each.value.vnet_address_space}/24"]
  vm_subnet_name     = "snet-dlp101"
  vm_subnet_cidr     = "${each.value.vnet_address_space}/24"

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  windows_vm_name = "vm-windows-${each.value.username}"
  vm_size         = "Standard_D2s_v5"
  username        = each.value.username
  password        = local.password

  environment = each.value.username

  bastion_host_id                   = module.module_bastion_host["bastion_host"].bastion_host.id
  bastion_host_resource_group_name  = module.module_bastion_host["bastion_host"].resource_group.name
  bastion_host_virtual_network_name = module.module_bastion_host["bastion_host"].virtual_network.name
  bastion_host_virtual_network_id   = module.module_bastion_host["bastion_host"].virtual_network.id
}

output "module_windows_virtual_machine" {
  value     = module.module_windows_virtual_machine[*]
  sensitive = true
}

resource "azapi_resource_action" "resource_action_create_link" {

  for_each = local.env_count > 0 ? local.bastion_hosts : {}

  type        = "Microsoft.Network/bastionHosts@2025-05-01"
  resource_id = module.module_bastion_host[each.key].bastion_host.id
  action      = "createShareableLinks"
  body = {
    vms = [
      for vm in module.module_windows_virtual_machine : {
        vm = {
          id = vm.windows_virtual_machine.id
        }
      }
    ]
  }
  response_export_values = ["*"]

}

output "shareable_links" {
  value = merge([
    for action in azapi_resource_action.resource_action_create_link : {
      for link in action.output.value : split("-", basename(link.vm.id))[1] => format("Fortinet123$%%^,%s%s,%s", split("-", basename(link.vm.id))[1], var.user_principal_domain, link.bsl)
    }
  ]...)
  sensitive = true
}