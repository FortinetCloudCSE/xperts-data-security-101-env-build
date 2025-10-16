locals {

  username_prefix = var.username_prefix
  user_count      = tonumber(var.user_count)
  user_start      = tonumber(var.user_start)

  rg-suffix             = var.rg-suffix
  location              = var.location
  password              = var.password
  user_principal_domain = var.user_principal_domain

  environments = {
    for i in range(local.user_start, local.user_start + local.user_count) :
    format("%s%02s", local.username_prefix, i) => { username = format("%s%02s", local.username_prefix, i) }
  }
}

module "module_data-security-101" {
  for_each = local.environments

  source = "./modules/azurerm"

  location                         = local.location
  rg-suffix                        = local.rg-suffix
  username                         = each.value.username
  password                         = local.password
  user_principal_domain            = local.user_principal_domain
  onedrive_license_group_object_id = var.onedrive_license_group_object_id
}

output "bastion_shareable_link" {
  value = [for key, rg in module.module_data-security-101 : format("%s, %s, %s", key, var.password, rg.bastion_shareable_links.value[0].bsl)]
}
