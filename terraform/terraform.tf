terraform {
  cloud {

    organization = "fortinetcloudcse"

    workspaces {
      name = "xperts-data-security-101-env-build"
    }
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">4.0"
    }
  }
  required_version = ">= 1.0.0"
}
