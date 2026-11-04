locals {
  # Portable size names -> Azure VM sizes. Any other value is passed through.
  vm_sizes = {
    small  = "Standard_B2s"
    medium = "Standard_D2s_v5"
    large  = "Standard_D4s_v5"
  }

  default_image = "Canonical:ubuntu-24_04-lts:server:latest"

  server_images = {
    for k, s in local.servers :
    # try() lets the precondition on the VM report a malformed image clearly.
    k => try(
      zipmap(["publisher", "offer", "sku", "version"], split(":", coalesce(s.image, local.default_image))),
      zipmap(["publisher", "offer", "sku", "version"], split(":", local.default_image)),
    )
  }
}

resource "azurerm_public_ip" "server" {
  for_each = { for k, s in local.servers : k => s if s.public_ip }

  name                = "pip-${local.name_prefix}-${each.key}"
  location            = var.region
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "server" {
  for_each = local.servers

  name                = "nic-${local.name_prefix}-${each.key}"
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.this[each.value.subnet].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.value.public_ip ? azurerm_public_ip.server[each.key].id : null
  }
}

resource "azurerm_linux_virtual_machine" "server" {
  for_each = local.servers

  name                            = "vm-${local.name_prefix}-${each.key}"
  location                        = var.region
  resource_group_name             = local.resource_group_name
  size                            = lookup(local.vm_sizes, each.value.size, each.value.size)
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.server[each.key].id]
  custom_data                     = each.value.user_data != null ? base64encode(each.value.user_data) : null

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = each.value.disk_size_gb
  }

  source_image_reference {
    publisher = local.server_images[each.key].publisher
    offer     = local.server_images[each.key].offer
    sku       = local.server_images[each.key].sku
    version   = local.server_images[each.key].version
  }

  identity {
    type = "SystemAssigned"
  }

  # Managed boot diagnostics (no storage account needed).
  boot_diagnostics {}

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.ssh_public_key != null
      error_message = "Azure Linux VMs require ssh_public_key (password login is disabled)."
    }
    precondition {
      condition     = each.value.image == null || length(split(":", coalesce(each.value.image, "x"))) == 4
      error_message = "On Azure, server image must be \"publisher:offer:sku:version\", e.g. \"Canonical:ubuntu-24_04-lts:server:latest\"."
    }
  }

  depends_on = [azurerm_subnet_nat_gateway_association.this, azurerm_subnet_network_security_group_association.this]
}
