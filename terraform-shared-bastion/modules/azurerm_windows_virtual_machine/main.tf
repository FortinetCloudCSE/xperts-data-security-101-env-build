locals {

  user_common = {
    user_principal_domain = var.user_principal_domain
    display_name_ext      = var.username
    password              = var.password
    usage_location        = "US"
    account_enabled       = true
  }

  windows_virtual_machine = {
    "vm-dlp-win" = {
      resource_group_name = azurerm_resource_group.resource_group.name
      location            = azurerm_resource_group.resource_group.location

      name = "vm-${var.username}-win"
      size = "Standard_D2s_v4"

      network_interface_ids = [azurerm_network_interface.network_interface.id]

      admin_username = var.username
      admin_password = var.password
      computer_name  = "vm-${var.username}-win"

      os_disk = {
        name                 = "disk-os-vm-${var.username}-win"
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

  virtual_machine_extension = {
    "vm-dlp-win" = {
      name                 = "cloudinit"
      virtual_machine_id   = azurerm_windows_virtual_machine.windows_virtual_machine.id
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
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
  lifecycle {
    ignore_changes = [tags]
  }
}

data "azurerm_subscription" "subscription" {
  subscription_id = var.subscription_id
}

resource "azurerm_virtual_network" "virtual_network" {
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  name          = var.vnet_name
  address_space = var.vnet_address_space
}

resource "azurerm_subnet" "subnet" {
  resource_group_name = azurerm_resource_group.resource_group.name

  name                 = var.vm_subnet_name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = [var.vm_subnet_cidr]
}

resource "azurerm_network_interface" "network_interface" {
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  name = "nic-windows-vm"
  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "windows_virtual_machine" {

  resource_group_name = local.windows_virtual_machine["vm-dlp-win"].resource_group_name
  location            = local.windows_virtual_machine["vm-dlp-win"].location

  name = local.windows_virtual_machine["vm-dlp-win"].name
  size = local.windows_virtual_machine["vm-dlp-win"].size

  network_interface_ids = local.windows_virtual_machine["vm-dlp-win"].network_interface_ids

  admin_username = local.windows_virtual_machine["vm-dlp-win"].admin_username
  admin_password = local.windows_virtual_machine["vm-dlp-win"].admin_password
  computer_name  = local.windows_virtual_machine["vm-dlp-win"].computer_name

  os_disk {
    name                 = local.windows_virtual_machine["vm-dlp-win"].os_disk.name
    caching              = local.windows_virtual_machine["vm-dlp-win"].os_disk.caching
    storage_account_type = local.windows_virtual_machine["vm-dlp-win"].os_disk.storage_account_type
  }

  allow_extension_operations = local.windows_virtual_machine["vm-dlp-win"].allow_extension_operations

  boot_diagnostics {
    storage_account_uri = local.windows_virtual_machine["vm-dlp-win"].boot_diagnostics.storage_account_uri
  }
  identity {
    type = local.windows_virtual_machine["vm-dlp-win"].identity.type
  }

  source_image_reference {
    publisher = local.windows_virtual_machine["vm-dlp-win"].source_image_reference.publisher
    offer     = local.windows_virtual_machine["vm-dlp-win"].source_image_reference.offer
    sku       = local.windows_virtual_machine["vm-dlp-win"].source_image_reference.sku
    version   = local.windows_virtual_machine["vm-dlp-win"].source_image_reference.version
  }

  custom_data = local.windows_virtual_machine["vm-dlp-win"].custom_data

  license_type = local.windows_virtual_machine["vm-dlp-win"].license_type
}

resource "azurerm_virtual_machine_extension" "virtual_machine_extension" {

  name                 = local.virtual_machine_extension["vm-dlp-win"].name
  virtual_machine_id   = local.virtual_machine_extension["vm-dlp-win"].virtual_machine_id
  publisher            = local.virtual_machine_extension["vm-dlp-win"].publisher
  type                 = local.virtual_machine_extension["vm-dlp-win"].type
  type_handler_version = local.virtual_machine_extension["vm-dlp-win"].type_handler_version
  settings             = local.virtual_machine_extension["vm-dlp-win"].settings
}

resource "azurerm_virtual_network_peering" "virtual_network_peering_bastion_host" {
  name                      = "bastion_to_vm_${var.environment}"
  resource_group_name       = var.bastion_host_resource_group_name
  virtual_network_name      = var.bastion_host_virtual_network_name
  remote_virtual_network_id = azurerm_virtual_network.virtual_network.id
}

resource "azurerm_virtual_network_peering" "virtual_network_peering_vm" {
  name                      = "vm_to_bastion"
  resource_group_name       = azurerm_resource_group.resource_group.name
  virtual_network_name      = azurerm_virtual_network.virtual_network.name
  remote_virtual_network_id = var.bastion_host_virtual_network_id
}

output "windows_virtual_machine" {
  value     = azurerm_windows_virtual_machine.windows_virtual_machine
  sensitive = true
}
