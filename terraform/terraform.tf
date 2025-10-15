terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">4.0"
    }
  }
  backend "azurerm" {
    key                   = "terraform.tfstate"
    use_oidc              = true
  }

  required_version = ">= 1.0.0"
}
