# ============================================================
# terraform/azure/main.tf
# Provisions the Azure VM that Ansible will then configure.
#
# What this creates:
#   - Resource Group
#   - Virtual Network + Subnet
#   - Network Security Group (SSH port 22, HTTP port 80)
#   - Public IP address
#   - Network Interface
#   - Ubuntu 22.04 VM with SSH key authentication
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
#
# After apply, copy the public_ip output into ansible/inventory.ini
# ============================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ── Variables ────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  default     = "epicbook-prod-rg"
}

variable "location" {
  description = "Azure region"
  default     = "East US 2"
}

variable "admin_username" {
  description = "SSH admin username for the VM"
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file"
  default     = "~/.ssh/id_ed25519.pub"
}

# ── Resource Group ────────────────────────────────────────────

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ── Networking ────────────────────────────────────────────────

resource "azurerm_virtual_network" "vnet" {
  name                = "epicbook-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "epicbook-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ── Network Security Group ────────────────────────────────────
# Only ports 22 (SSH admin access) and 80 (HTTP app traffic) are open.
# All other inbound traffic is blocked by default.

resource "azurerm_network_security_group" "nsg" {
  name                = "epicbook-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ── Public IP ─────────────────────────────────────────────────

resource "azurerm_public_ip" "pip" {
  name                = "epicbook-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ── Network Interface ─────────────────────────────────────────

resource "azurerm_network_interface" "nic" {
  name                = "epicbook-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ── Virtual Machine ───────────────────────────────────────────
# Ubuntu 22.04 LTS with SSH key authentication.
# Password authentication is disabled for security.

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "epicbook-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # Disable password authentication - SSH keys only
  disable_password_authentication = true
}

# ── Outputs ───────────────────────────────────────────────────
# After 'terraform apply', copy these values into ansible/inventory.ini

output "public_ip" {
  description = "Public IP address of the VM - use this in ansible/inventory.ini"
  value       = azurerm_public_ip.pip.ip_address
}

output "admin_user" {
  description = "SSH username for Ansible to connect with"
  value       = var.admin_username
}

output "ssh_command" {
  description = "Ready-to-use SSH command to verify VM access"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}
