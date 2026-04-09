# ── Location ──────────────────────────────────────────────────────────────────
variable "location" {
  type        = string
  description = <<-EOT
    Azure regio voor ACA resources. GPU workload profiles zijn regio-specifiek:
    - Consumption (CPU):                alle regio's
    - Consumption-GPU-NC8as-T4 (T4):   swedencentral, eastus, westus3, ...
    - Consumption-GPU-NC24-A100 (A100): swedencentral, eastus
    Standaard: swedencentral — ondersteunt alle GPU-typen en is dichtbij Nederland.
  EOT
  default     = "swedencentral"
}

# ── Naming ────────────────────────────────────────────────────────────────────
variable "resource_group_name" {
  type        = string
  description = "Resource group voor alle ACA resources. Aparte RG van de VM-setup."
  default     = "rg-ollama-aca-prod"
}

# ── Workload Profile ──────────────────────────────────────────────────────────
variable "workload_profile_type" {
  type        = string
  description = <<-EOT
    ACA workload profile type. Bepaalt GPU-beschikbaarheid en kosten:
    - "Consumption"                    : CPU-only, gratis bij scale-to-zero. Standaard.
    - "Consumption-GPU-NC8as-T4"       : Serverless NVIDIA T4, ~€1/uur actief.
    - "Consumption-GPU-NC24-A100"      : Serverless NVIDIA A100, ~€3,50/uur actief. OVERSCHRIJDT budget bij normaal gebruik.
    LET OP: GPU-profielen vereisen quota-aanvraag bij Azure Support vóór gebruik.
    LET OP: westeurope ondersteunt GEEN GPU workload profiles in ACA.
  EOT
  default     = "Consumption"
}

variable "workload_profile_name" {
  type        = string
  description = "Naam van het workload profile in de ACA environment."
  default     = "ollama-profile"
}

# ── Scaling ───────────────────────────────────────────────────────────────────
variable "min_replicas" {
  type        = number
  description = "Minimum aantal replicas. 0 = scale-to-zero (vereist tolerantie voor cold start)."
  default     = 0
}

variable "max_replicas" {
  type        = number
  description = "Maximum aantal replicas. 1 is voldoende voor Ollama (single-model server)."
  default     = 1
}

variable "scale_cooldown_period_seconds" {
  type        = number
  description = "Seconden inactiviteit voordat ACA schaalt naar 0. Standaard 900 = 15 minuten."
  default     = 900
}

# ── Container ─────────────────────────────────────────────────────────────────
variable "ollama_image" {
  type        = string
  description = "Ollama container image. Zelfde image voor CPU en GPU — GPU wordt automatisch gedetecteerd."
  default     = "ollama/ollama:latest"
}

variable "container_cpu" {
  type        = number
  description = <<-EOT
    CPU cores voor de Ollama container.
    Consumption (CPU): 0.5 of 1.0
    Consumption-GPU-NC8as-T4: maximaal 8
    Consumption-GPU-NC24-A100: maximaal 24
    CPU en memory moeten een geldig ACA-paar zijn (zie Azure docs).
  EOT
  default     = 0.5
}

variable "container_memory" {
  type        = string
  description = <<-EOT
    Geheugen voor de Ollama container. Moet overeenkomen met het workload profile.
    Consumption: "1Gi" (bij 0.5 CPU) of "2Gi" (bij 1 CPU)
    NC8as-T4: bijv. "56Gi"
    NC24-A100: bijv. "220Gi"
  EOT
  default     = "1Gi"
}

variable "ollama_port" {
  type        = number
  description = "Poort waarop Ollama luistert in de container."
  default     = 11434
}

# ── Storage ───────────────────────────────────────────────────────────────────
variable "storage_account_name" {
  type        = string
  description = <<-EOT
    Naam van het Azure Storage account voor de Ollama model file share.
    Moet globaal uniek zijn — 3-24 kleine letters en cijfers.
    Als de naam al bezet is, instellen via GitHub Variable ACA_STORAGE_ACCOUNT_NAME.
  EOT
  default     = "stollamaacamodels"
}

variable "file_share_quota_gb" {
  type        = number
  description = "Azure Files share quota in GiB. Minimaal 128 GiB voor een paar middelgrote modellen."
  default     = 128
}

# ── Access Control ────────────────────────────────────────────────────────────
variable "allowed_ip" {
  type        = string
  description = "Jouw publieke IPv4-adres (zonder /32). Alleen dit IP kan de Ollama API bereiken."
}

# ── Tags ──────────────────────────────────────────────────────────────────────
variable "tags" {
  type = map(string)
  default = {
    project = "ollama"
    managed = "terraform"
  }
}
