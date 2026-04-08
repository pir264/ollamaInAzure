terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  backend "azurerm" {
    # Values are injected at 'terraform init' time via -backend-config flags in the deploy workflow.
    # Do NOT hardcode values here — they come from GitHub Secrets.
    resource_group_name  = ""
    storage_account_name = ""
    container_name       = ""
    key                  = "ollama/terraform.tfstate"
  }
}
