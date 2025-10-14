terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">4.0"
    }
  }
  backend "local" {}
  required_version = ">= 1.0.0"
}
