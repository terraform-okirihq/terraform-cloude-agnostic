# --- Resource group --------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 1 : 0

  name     = "rg-${local.name_prefix}"
  location = var.region
  tags     = local.tags
}

locals {
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : one(azurerm_resource_group.this[*].name)

  # Storage account names: 3-24 chars, lowercase letters and digits only,
  # globally unique. 16 chars of prefix + 8 hex chars of randomness.
  storage_prefix = substr(replace(lower(local.name_prefix), "/[^a-z0-9]/", ""), 0, 16)
}

# --- Network ---------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name_prefix}"
  location            = var.region
  resource_group_name = local.resource_group_name
  address_space       = [var.network_cidr]

  tags = local.tags
}

resource "azurerm_subnet" "this" {
  for_each = local.subnets

  name                            = "snet-${local.name_prefix}-${each.key}"
  resource_group_name             = local.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [each.value.cidr]
  default_outbound_access_enabled = each.value.public
}

# --- Storage ---------------------------------------------------------------

resource "random_id" "storage" {
  count       = var.create_storage_bucket ? 1 : 0
  byte_length = 4
}

resource "azurerm_storage_account" "this" {
  count = var.create_storage_bucket ? 1 : 0

  name                              = "${local.storage_prefix}${random_id.storage[0].hex}"
  resource_group_name               = local.resource_group_name
  location                          = var.region
  account_tier                      = "Standard"
  account_replication_type          = var.storage_replication_type
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true

  sas_policy {
    expiration_period = "1.00:00:00"
    expiration_action = "Log"
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  count = var.create_storage_bucket ? 1 : 0

  name                  = "data"
  storage_account_id    = azurerm_storage_account.this[0].id
  container_access_type = "private"
}

resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  count = var.create_storage_bucket ? 1 : 0

  name                       = "blob-to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.this[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}
