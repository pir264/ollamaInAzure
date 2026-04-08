output "public_ip_address" {
  description = "Statisch publiek IP-adres van de Ollama VM."
  value       = azurerm_public_ip.ollama.ip_address
}

output "ssh_command" {
  description = "SSH-commando om verbinding te maken met de VM."
  value       = "ssh ${azurerm_linux_virtual_machine.ollama.admin_username}@${azurerm_public_ip.ollama.ip_address}"
}

output "ollama_api_url" {
  description = "Ollama REST API endpoint."
  value       = "http://${azurerm_public_ip.ollama.ip_address}:${var.ollama_port}"
}

output "vm_id" {
  description = "Azure resource ID van de VM."
  value       = azurerm_linux_virtual_machine.ollama.id
}

output "resource_group_name" {
  description = "Resource group met alle Ollama-resources."
  value       = azurerm_resource_group.ollama.name
}
