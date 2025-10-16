locals {

  user_common = {
    user_principal_domain = var.user_principal_domain
    display_name_ext      = var.username
    password              = var.password
    usage_location        = "US"
    account_enabled       = true
  }

  public_ips = {
    "pip-bastion" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name                 = "pip-bastion"
      allocation_method    = "Static"
      ddos_protection_mode = "Disabled"
    }
  }

  virtual_networks = {
    "data-security-101-vnet" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name          = "data-security-101-vnet"
      address_space = ["10.0.0.0/16"]
    }
  }

  subnets = {
    "snet-win-vm" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name                 = "snet-win-vm"
      address_prefix       = ["10.0.1.0/25"]
      virtual_network_name = azurerm_virtual_network.virtual_network["data-security-101-vnet"].name
    }
    "AzureBastionSubnet" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name                 = "AzureBastionSubnet"
      address_prefix       = ["10.0.1.128/25"]
      virtual_network_name = azurerm_virtual_network.virtual_network["data-security-101-vnet"].name
    }
  }

  network_interfaces = {
    "nic-win-vm" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name = "nic-win-vm"

      ip_configurations = [
        {
          name                          = "ipconfig1"
          primary                       = true
          subnet_id                     = azurerm_subnet.subnet["snet-win-vm"].id
          private_ip_address_allocation = "Dynamic"
          public_ip_address_id          = null
        }
      ]
    }
  }

  windows_virtual_machines = {
    "vm-dlp-win" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name = "vm-dlp-win"
      size = "Standard_D2s_v4"

      network_interface_ids = [azurerm_network_interface.network_interface["nic-win-vm"].id]

      admin_username = var.username
      admin_password = var.password
      computer_name  = "vm-dlp-win"

      os_disk = {
        name                 = "disk-os-vm-dlp-win"
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
      }

      allow_extension_operations = true

      boot_diagnostics = {
        storage_account_uri = null
      }
      identity = {
        type = "SystemAssigned"
      }

      source_image_reference = {
        publisher = "MicrosoftWindowsDesktop"
        offer     = "Windows-10"
        sku       = "win10-22h2-pro-g2"
        version   = "latest"
      }

      custom_data = base64encode(local.vm_custom_data)

      license_type = "Windows_Client"
    }
  }

  bastion_hosts = {
    "bastion-host" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name                   = azurerm_windows_virtual_machine.windows_virtual_machine["vm-dlp-win"].name
      sku                    = "Standard"
      shareable_link_enabled = true

      ip_configuration = {
        name                 = "ipconfig1"
        subnet_id            = azurerm_subnet.subnet["AzureBastionSubnet"].id
        public_ip_address_id = azurerm_public_ip.public_ip["pip-bastion"].id
      }
    }
  }

  virtual_machine_extensions = {
    "vm-dlp-win" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name                 = "cloudinit"
      virtual_machine_id   = azurerm_windows_virtual_machine.windows_virtual_machine["vm-dlp-win"].id
      publisher            = "Microsoft.Compute"
      type                 = "CustomScriptExtension"
      type_handler_version = "1.10"
      settings             = <<SETTINGS
    {
        "commandToExecute": "powershell -ExecutionPolicy unrestricted -NoProfile -NonInteractive -command \"cp c:/azuredata/customdata.bin c:/azuredata/forticlientinstall.ps1; c:/azuredata/forticlientinstall.ps1\""
    }
    SETTINGS
    }
  }

  resource_action_create_links = {
    create_link = {
      type        = "Microsoft.Network/bastionHosts@2022-05-01"
      name        = "createLink"
      resource_id = azurerm_bastion_host.bastion_host["bastion-host"].id
      action      = "createShareableLinks"
      body = {
        vms = [
          {
            vm = {
              id = azurerm_windows_virtual_machine.windows_virtual_machine["vm-dlp-win"].id
            }
          }
        ]
      }
    }
  }

  resource_action_get_links = {
    get_link = {
      type                   = "Microsoft.Network/bastionHosts@2022-05-01"
      name                   = "getLink"
      resource_id            = azurerm_bastion_host.bastion_host["bastion-host"].id
      action                 = "getShareableLinks"
      response_export_values = ["*"]
      #depends_on             = [azapi_resource_action.resource_action_create_link["create_link"]]
    }
  }


  vm_custom_data = <<-EOT
Write-Host "Enable HTTPS in WinRM"
$WinRmHttps = "@{Hostname=`"$RemoteHostName`"; CertificateThumbprint=`"$Thumbprint`"}"
winrm create winrm/config/Listener?Address=*+Transport=HTTPS $WinRmHttps

Write-Host "Set Basic Auth in WinRM"
$WinRmBasic = "@{Basic=`"true`"}"
winrm set winrm/config/service/Auth $WinRmBasic 

Write-Host "Open Firewall Ports"
netsh advfirewall firewall add rule name="Windows Remote Management (HTTP-In)" dir=in action=allow protocol=TCP localport=5985

netsh advfirewall firewall add rule name="Windows Remote Management (HTTPS-In)" dir=in action=allow protocol=TCP localport=5986

$Path = $env:TEMP
$Installer = "chrome_installer.exe"
Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile "$Path\$Installer"
Start-Process -FilePath "$Path\$Installer" -Args "/silent /install" -Verb RunAs -Wait
Remove-Item "$Path\$Installer"

#Enable bookmark bar and add bookmarks in chrome 

$registryPath = 'HKLM:\Software\Policies\Google\Chrome' 
$enableBookmarkBar = 1 #set as 0 to disable it. 
if (-not(Test-Path $registryPath)) { 
    New-Item -Path $registryPath -Force | Out-Null  
} 
#setting BookmarkBarEnabled registry name 
Set-ItemProperty -Path $registryPath -Name BookmarkBarEnabled -Value $enableBookmarkBar -Force | Out-Null 
Write-Host "Chrome policy key created and bookmark bar enabled." 

# add required bookmarks 
$bookmarkJson = '[ 
    {
        "toplevel_name": "FortiDLP" 
    }, 
    { 
        "name": "FortiDLP", 
        "url": "https://fortidlp-training.reveal.nextdlp.com/" 
    }, 
    { 
        "name": "DLP Policy Testing Tool", 
        "url": "https://dlptest.ai/" 
    }, 
    { 
        "name": "OneDrive", 
        "url": "https://onedrive.live.com/login" 
    }
]'
Set-ItemProperty -Path $registryPath -Name ManagedBookmarks -Value $bookmarkJson -Force | Out-Null
Write-Host "ManagedBookmarks registry key created and bookmarks added."

EOT
}

resource "azuread_user" "user" {

  user_principal_name = format("%s%s", var.username, local.user_common["user_principal_domain"])
  display_name        = var.username
  mail_nickname       = format("%s%s", var.username, local.user_common["display_name_ext"])
  mail                = format("%s%s", var.username, local.user_common["user_principal_domain"])
  password            = local.user_common["password"]
  account_enabled     = local.user_common["account_enabled"]
  usage_location      = local.user_common["usage_location"]
}

resource "azuread_group_member" "group_member" {

  group_object_id  = var.onedrive_license_group_object_id
  member_object_id = azuread_user.user.object_id
}

resource "azurerm_resource_group" "resource_group" {
  name     = "${var.username}-${var.rg-suffix}"
  location = var.location

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_public_ip" "public_ip" {
  for_each = local.public_ips

  resource_group_name = each.value.resource_group_name
  location            = each.value.location

  name                 = each.value.name
  allocation_method    = each.value.allocation_method
  ddos_protection_mode = each.value.ddos_protection_mode
}

resource "azurerm_virtual_network" "virtual_network" {
  for_each = local.virtual_networks

  resource_group_name = each.value.resource_group_name
  location            = each.value.location

  name          = each.value.name
  address_space = each.value.address_space
}

resource "azurerm_subnet" "subnet" {
  for_each = local.subnets

  resource_group_name = each.value.resource_group_name

  name                 = each.value.name
  address_prefixes     = each.value.address_prefix
  virtual_network_name = each.value.virtual_network_name
}

resource "azurerm_network_interface" "network_interface" {
  for_each = local.network_interfaces

  resource_group_name = each.value.resource_group_name
  location            = each.value.location

  name = each.value.name

  dynamic "ip_configuration" {
    for_each = each.value.ip_configurations
    content {
      name                          = ip_configuration.value.name
      primary                       = ip_configuration.value.primary
      subnet_id                     = ip_configuration.value.subnet_id
      private_ip_address_allocation = ip_configuration.value.private_ip_address_allocation
      public_ip_address_id          = ip_configuration.value.public_ip_address_id
    }
  }
}

resource "azurerm_windows_virtual_machine" "windows_virtual_machine" {
  for_each = local.windows_virtual_machines

  resource_group_name = each.value.resource_group_name
  location            = each.value.location

  name = each.value.name
  size = each.value.size

  network_interface_ids = each.value.network_interface_ids

  admin_username = each.value.admin_username
  admin_password = each.value.admin_password
  computer_name  = each.value.computer_name

  os_disk {
    name                 = each.value.os_disk.name
    caching              = each.value.os_disk.caching
    storage_account_type = each.value.os_disk.storage_account_type
  }

  allow_extension_operations = each.value.allow_extension_operations

  boot_diagnostics {
    storage_account_uri = each.value.boot_diagnostics.storage_account_uri
  }
  identity {
    type = each.value.identity.type
  }

  source_image_reference {
    publisher = each.value.source_image_reference.publisher
    offer     = each.value.source_image_reference.offer
    sku       = each.value.source_image_reference.sku
    version   = each.value.source_image_reference.version
  }

  custom_data = each.value.custom_data

  license_type = each.value.license_type
}

resource "azurerm_virtual_machine_extension" "virtual_machine_extension" {
  for_each = local.virtual_machine_extensions

  name                 = each.value.name
  virtual_machine_id   = each.value.virtual_machine_id
  publisher            = each.value.publisher
  type                 = each.value.type
  type_handler_version = each.value.type_handler_version
  settings             = each.value.settings
}

resource "azurerm_bastion_host" "bastion_host" {
  for_each = local.bastion_hosts

  resource_group_name = each.value.resource_group_name
  location            = each.value.location

  name                   = each.value.name
  sku                    = each.value.sku
  shareable_link_enabled = each.value.shareable_link_enabled

  ip_configuration {
    name                 = each.value.ip_configuration.name
    subnet_id            = each.value.ip_configuration.subnet_id
    public_ip_address_id = each.value.ip_configuration.public_ip_address_id
  }
}

resource "azapi_resource_action" "resource_action_create_link" {
  for_each = local.resource_action_create_links

  type        = each.value.type
  resource_id = each.value.resource_id
  action      = each.value.action
  body        = each.value.body
}

data "azapi_resource_action" "resource_action_get_link" {
  for_each = local.resource_action_get_links

  type                   = each.value.type
  resource_id            = each.value.resource_id
  action                 = each.value.action
  response_export_values = each.value.response_export_values
  depends_on             = [azapi_resource_action.resource_action_create_link["create_link"]]
}

output "bastion_shareable_links" {
  value = data.azapi_resource_action.resource_action_get_link["get_link"].output
}