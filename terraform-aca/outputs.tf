output "ollama_api_url" {
  description = "HTTPS endpoint voor de Ollama REST API. ACA beheert TLS automatisch."
  value       = "https://${azurerm_container_app.ollama.latest_revision_fqdn}"
}

output "container_app_fqdn" {
  description = "Volledig gekwalificeerde domeinnaam van de Container App."
  value       = azurerm_container_app.ollama.latest_revision_fqdn
}

output "resource_group_name" {
  description = "Resource group met alle ACA Ollama resources."
  value       = azurerm_resource_group.ollama_aca.name
}

output "storage_account_name" {
  description = "Storage account naam voor de model file share."
  value       = azurerm_storage_account.ollama_aca.name
}

output "file_share_name" {
  description = "Azure Files share naam voor Ollama modellen."
  value       = azurerm_storage_share.ollama_models.name
}

output "workload_profile_type" {
  description = "Actief workload profile type."
  value       = var.workload_profile_type
}

output "cost_advisory" {
  description = "Kosten-advies op basis van het geselecteerde profile."
  value = var.workload_profile_type == "Consumption" ? (
    "CPU-only Consumption: gratis bij scale-to-zero. Alleen always-on kosten: ~€14-17/maand (storage + logs)."
    ) : var.workload_profile_type == "Consumption-GPU-NC8as-T4" ? (
    "T4 GPU serverless: ~€1/uur actief. Bij 2u/dag x 22 werkdagen: ~€61/maand totaal. Binnen budget."
    ) : (
    "WAARSCHUWING: A100 GPU geselecteerd. Bij 2u/dag x 22 werkdagen: ~€171/maand. OVERSCHRIJDT het budget van €100/maand."
  )
}

output "cold_start_warning" {
  description = "Verwachte cold start tijd bij eerste request na inactiviteit."
  value       = "Container startup: 30-90 sec. Model laden van Azure Files: 1-5 min afhankelijk van modelgrootte. Stel je client timeout in op minimaal 5 minuten."
}
