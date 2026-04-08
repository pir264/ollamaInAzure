# ── Location ─────────────────────────────────────────────────────────────────
variable "location" {
  type        = string
  description = "Azure region voor alle resources."
  default     = "westeurope"
}

# ── Naming ────────────────────────────────────────────────────────────────────
variable "resource_group_name" {
  type        = string
  description = "Naam van de resource group."
  default     = "rg-ollama-prod"
}

variable "vm_name" {
  type        = string
  description = "Naam van de virtuele machine."
  default     = "vm-ollama"
}

# ── VM Performance ────────────────────────────────────────────────────────────
variable "vm_size" {
  type        = string
  description = "Azure VM SKU. Aanpasbaar via GitHub Variable VM_SIZE zonder code te wijzigen."
  default     = "Standard_D8s_v5"
}

variable "vm_os_disk_size_gb" {
  type        = number
  description = "OS disk grootte in GB."
  default     = 30
}

variable "vm_data_disk_size_gb" {
  type        = number
  description = "Data disk grootte in GB voor Ollama model-opslag."
  default     = 128
}

variable "vm_data_disk_sku" {
  type        = string
  description = "Data disk SKU. Premium_LRS voor snelheid, Standard_LRS voor kosten."
  default     = "Premium_LRS"
}

# ── OS / Auth ─────────────────────────────────────────────────────────────────
variable "admin_username" {
  type        = string
  description = "Linux admin gebruikersnaam voor SSH."
  default     = "ollamaadmin"
}

variable "ssh_public_key" {
  type        = string
  description = "RSA of ED25519 publieke sleutel voor SSH-toegang."
  sensitive   = true
}

# ── Network / Access ──────────────────────────────────────────────────────────
variable "allowed_ip" {
  type        = string
  description = "IPv4-adres (zonder CIDR) dat toegang krijgt via de NSG. Jouw thuis- of werk-IP."
}

variable "ollama_port" {
  type        = number
  description = "Poort waarop Ollama luistert."
  default     = 11434
}

# ── Ollama ────────────────────────────────────────────────────────────────────
variable "default_model" {
  type        = string
  description = "Eerste Ollama-model dat na provisioning wordt gepulled (bijv. gemma4:latest, llama3.2)."
  default     = "gemma4:latest"
}
