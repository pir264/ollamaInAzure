terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  backend "azurerm" {
    # Zelfde storage account als de VM-state, maar een andere key.
    # Values worden geïnjecteerd via -backend-config flags in deploy-aca.yml.
    resource_group_name  = ""
    storage_account_name = ""
    container_name       = ""
    key                  = "ollama-aca/terraform.tfstate"
  }
}
