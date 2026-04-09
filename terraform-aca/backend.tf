terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # azapi geeft directe toegang tot de Azure REST API.
    # Gebruikt voor het ACA environment omdat azurerm 4.x een bug heeft
    # waarbij MinimumCount altijd wordt meegestuurd (niet ondersteund voor GPU Consumption profielen).
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
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
