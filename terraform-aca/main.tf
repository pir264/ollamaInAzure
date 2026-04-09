provider "azurerm" {
  features {}
}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "ollama_aca" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ── Log Analytics Workspace (vereist door ACA environment) ────────────────────
resource "azurerm_log_analytics_workspace" "ollama_aca" {
  name                = "law-ollama-aca"
  location            = azurerm_resource_group.ollama_aca.location
  resource_group_name = azurerm_resource_group.ollama_aca.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ── Storage Account (Premium FileStorage voor Azure Files) ────────────────────
# Premium FileStorage biedt betere IOPS voor model-laden dan Standard.
# LRS is voldoende — modellen zijn herdownloadbaar, geen productie-data.
resource "azurerm_storage_account" "ollama_aca" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.ollama_aca.name
  location                 = azurerm_resource_group.ollama_aca.location
  account_tier             = "Premium"
  account_kind             = "FileStorage"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_storage_share" "ollama_models" {
  name                 = "ollama-models"
  storage_account_name = azurerm_storage_account.ollama_aca.name
  quota                = var.file_share_quota_gb
  # SMB protocol (standaard) — geen custom VNet vereist.
}

# ── Container App Environment ─────────────────────────────────────────────────
# Bij workload_profile_type = "Consumption" is het ingebouwde Consumption profile
# al aanwezig; geen extra workload_profile blok nodig.
# Bij GPU-types wordt het profiel dynamisch toegevoegd.
resource "azurerm_container_app_environment" "ollama_aca" {
  name                       = "cae-ollama-aca"
  location                   = azurerm_resource_group.ollama_aca.location
  resource_group_name        = azurerm_resource_group.ollama_aca.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.ollama_aca.id
  tags                       = var.tags

  # Alleen een workload_profile blok toevoegen als een GPU-type is gekozen.
  # Consumption GPU-profielen zijn serverless (geen min/max count).
  dynamic "workload_profile" {
    for_each = var.workload_profile_type != "Consumption" ? [1] : []
    content {
      name                  = var.workload_profile_name
      workload_profile_type = var.workload_profile_type
    }
  }
}

# ── ACA Environment Storage (registreert de Azure Files share) ────────────────
# Koppelt het storage account aan de ACA environment zodat containers
# de share kunnen mounten via een volume definitie.
resource "azurerm_container_app_environment_storage" "ollama_models" {
  name                         = "ollama-models-storage"
  container_app_environment_id = azurerm_container_app_environment.ollama_aca.id
  account_name                 = azurerm_storage_account.ollama_aca.name
  share_name                   = azurerm_storage_share.ollama_models.name
  access_key                   = azurerm_storage_account.ollama_aca.primary_access_key
  access_mode                  = "ReadWrite"
}

# ── Container App ─────────────────────────────────────────────────────────────
resource "azurerm_container_app" "ollama" {
  name                         = "ca-ollama"
  container_app_environment_id = azurerm_container_app_environment.ollama_aca.id
  resource_group_name          = azurerm_resource_group.ollama_aca.name
  revision_mode                = "Single"
  tags                         = var.tags

  # ── Ingress ────────────────────────────────────────────────────────────────
  # ACA termineert TLS automatisch op poort 443.
  # De container ontvangt HTTP op target_port.
  # ip_security_restriction met action = "Allow" maakt een impliciete deny-all
  # voor alle andere IP-adressen.
  ingress {
    external_enabled = true
    target_port      = var.ollama_port
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }

    ip_security_restriction {
      action           = "Allow"
      ip_address_range = "${var.allowed_ip}/32"
      name             = "AllowMyIP"
      description      = "Alleen toegang vanaf het opgegeven IP-adres."
    }
  }

  # ── Template ───────────────────────────────────────────────────────────────
  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # HTTP scale rule: wekt de container zodra er een request binnenkomt.
    # concurrent_requests = "1" betekent: schaal op bij het eerste wachtende request.
    http_scale_rule {
      name                = "http-scaler"
      concurrent_requests = "1"
    }

    # Custom KEDA HTTP scaler met expliciete cooldownPeriod van 15 minuten (900 sec).
    # Dit overschrijft de platform-standaard van ~5 minuten.
    custom_scale_rule {
      name             = "http-cooldown"
      custom_rule_type = "http"
      metadata = {
        targetPendingRequests = "1"
        cooldownPeriod        = tostring(var.scale_cooldown_period_seconds)
      }
    }

    # ── Container ─────────────────────────────────────────────────────────────
    container {
      name   = "ollama"
      image  = var.ollama_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name  = "OLLAMA_HOST"
        value = "0.0.0.0:${var.ollama_port}"
      }

      env {
        name  = "OLLAMA_MODELS"
        value = "/mnt/models"
      }

      # Houdt het model 15 minuten in geheugen na het laatste request.
      # Sluit aan op de scale-down cooldown zodat een actief model niet
      # wordt verwijderd voordat de container schaalt naar 0.
      env {
        name  = "OLLAMA_KEEP_ALIVE"
        value = "15m"
      }

      volume_mounts {
        name = "ollama-models"
        path = "/mnt/models"
      }

      # Liveness probe: herstart de container als Ollama niet meer reageert.
      liveness_probe {
        transport               = "HTTP"
        port                    = var.ollama_port
        path                    = "/api/tags"
        initial_delay           = 60
        interval_seconds        = 30
        timeout                 = 10
        failure_count_threshold = 3
      }

      # Readiness probe: wacht met traffic sturen tot Ollama klaar is.
      # Kritiek bij cold starts — model laden van Azure Files kan 1-5 min duren.
      # initial_delay is niet ondersteund in readiness_probe (alleen in liveness_probe).
      # failure_count_threshold = 10 x interval_seconds 10 = 100 sec wachttijd voor startup.
      readiness_probe {
        transport               = "HTTP"
        port                    = var.ollama_port
        path                    = "/api/tags"
        interval_seconds        = 10
        timeout                 = 5
        success_count_threshold = 1
        failure_count_threshold = 10
      }
    }

    # ── Volume ────────────────────────────────────────────────────────────────
    # Verwijst naar de storage geregistreerd via azurerm_container_app_environment_storage.
    volume {
      name         = "ollama-models"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.ollama_models.name
    }
  }

  # Bij Consumption: gebruik het ingebouwde "Consumption" profiel.
  # Bij GPU-types: gebruik het aangemaakte workload profile.
  # Bij een Consumption-only environment mag workload_profile_name NIET worden opgegeven.
  # Bij GPU-profielen verwijst het naar het profiel dat in de environment is aangemaakt.
  workload_profile_name = var.workload_profile_type == "Consumption" ? null : var.workload_profile_name

  depends_on = [
    azurerm_container_app_environment_storage.ollama_models,
  ]
}
