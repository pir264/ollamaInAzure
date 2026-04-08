provider "azurerm" {
  features {}
}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "ollama" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "ollama"
    managed = "terraform"
  }
}

# ── Networking ────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "ollama" {
  name                = "vnet-ollama"
  location            = azurerm_resource_group.ollama.location
  resource_group_name = azurerm_resource_group.ollama.name
  address_space       = ["10.0.0.0/16"]
  tags                = azurerm_resource_group.ollama.tags
}

resource "azurerm_subnet" "ollama" {
  name                 = "snet-ollama"
  resource_group_name  = azurerm_resource_group.ollama.name
  virtual_network_name = azurerm_virtual_network.ollama.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Statisch IP zodat het adres niet verandert bij deallocate/start.
resource "azurerm_public_ip" "ollama" {
  name                = "pip-ollama"
  location            = azurerm_resource_group.ollama.location
  resource_group_name = azurerm_resource_group.ollama.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.ollama.tags
}

resource "azurerm_network_security_group" "ollama" {
  name                = "nsg-ollama"
  location            = azurerm_resource_group.ollama.location
  resource_group_name = azurerm_resource_group.ollama.name
  tags                = azurerm_resource_group.ollama.tags

  # SSH — alleen van jouw IP
  security_rule {
    name                       = "AllowSSHFromMyIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${var.allowed_ip}/32"
    destination_address_prefix = "*"
  }

  # Ollama API — alleen van jouw IP
  security_rule {
    name                       = "AllowOllamaFromMyIP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.ollama_port)
    source_address_prefix      = "${var.allowed_ip}/32"
    destination_address_prefix = "*"
  }

  # Blokkeer al het overige inkomende verkeer
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "ollama" {
  name                = "nic-ollama"
  location            = azurerm_resource_group.ollama.location
  resource_group_name = azurerm_resource_group.ollama.name
  tags                = azurerm_resource_group.ollama.tags

  ip_configuration {
    name                          = "ipconfig-ollama"
    subnet_id                     = azurerm_subnet.ollama.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ollama.id
  }
}

resource "azurerm_network_interface_security_group_association" "ollama" {
  network_interface_id      = azurerm_network_interface.ollama.id
  network_security_group_id = azurerm_network_security_group.ollama.id
}

# ── Data Disk (model-opslag, blijft bestaan bij VM-vervanging) ─────────────────
resource "azurerm_managed_disk" "ollama_models" {
  name                 = "disk-ollama-models"
  location             = azurerm_resource_group.ollama.location
  resource_group_name  = azurerm_resource_group.ollama.name
  storage_account_type = var.vm_data_disk_sku
  create_option        = "Empty"
  disk_size_gb         = var.vm_data_disk_size_gb
  tags                 = azurerm_resource_group.ollama.tags
}

# ── Virtual Machine ───────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "ollama" {
  name                = var.vm_name
  location            = azurerm_resource_group.ollama.location
  resource_group_name = azurerm_resource_group.ollama.name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = azurerm_resource_group.ollama.tags

  network_interface_ids = [
    azurerm_network_interface.ollama.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.vm_os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Cloud-init wordt alleen uitgevoerd bij de eerste boot.
  # Volgende deallocate/start-cycli slaan dit over.
  custom_data = base64encode(templatefile("${path.module}/../scripts/cloud-init.yml", {
    admin_username = var.admin_username
    ollama_port    = var.ollama_port
    default_model  = var.default_model
  }))

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "ollama_models" {
  managed_disk_id    = azurerm_managed_disk.ollama_models.id
  virtual_machine_id = azurerm_linux_virtual_machine.ollama.id
  lun                = 0
  caching            = "ReadWrite"
}

# ── Auto-shutdown (backup voor de GitHub Actions cron) ────────────────────────
# 19:00 UTC = 20:00 CET (winter) / 21:00 CEST (zomer)
# De GitHub Actions scheduled-stop workflow dekt de zomertijdovergang af.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "ollama" {
  virtual_machine_id = azurerm_linux_virtual_machine.ollama.id
  location           = azurerm_resource_group.ollama.location
  enabled            = true

  daily_recurrence_time = "1900"
  timezone              = "UTC"

  notification_settings {
    enabled = false
  }
}
