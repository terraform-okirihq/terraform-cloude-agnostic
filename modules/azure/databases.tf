locals {
  db_skus = {
    postgres = { small = "B_Standard_B1ms", medium = "GP_Standard_D2ds_v5", large = "GP_Standard_D4ds_v5" }
    mysql    = { small = "B_Standard_B1ms", medium = "GP_Standard_D2ds_v4", large = "GP_Standard_D4ds_v4" }
  }

  postgres_dbs = { for k, d in local.databases : k => d if d.engine == "postgres" }
  mysql_dbs    = { for k, d in local.databases : k => d if d.engine == "mysql" }

  # PostgreSQL Flexible Server only accepts these storage sizes (GB).
  pg_storage_sizes = [32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384]

  db_subnet_id = azurerm_subnet.this[local.default_subnet].id

  private_dns_zones = merge(
    length(local.postgres_dbs) > 0 ? { postgres = "privatelink.postgres.database.azure.com" } : {},
    length(local.mysql_dbs) > 0 ? { mysql = "privatelink.mysql.database.azure.com" } : {},
  )
}

resource "random_password" "databases" {
  for_each = local.databases

  length           = 32
  special          = true
  override_special = "!#%*-_=+"
}

resource "azurerm_private_dns_zone" "databases" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "databases" {
  for_each = local.private_dns_zones

  name                = "${local.name_prefix}-${each.key}"
  private_dns_zone_id = azurerm_private_dns_zone.databases[each.key].id
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = local.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  for_each = local.postgres_dbs

  name                          = "psql-${local.name_prefix}-${each.key}-${local.suffix}"
  location                      = var.region
  resource_group_name           = local.resource_group_name
  version                       = each.value.version
  sku_name                      = local.db_skus.postgres[each.value.size]
  storage_mb                    = [for s in local.pg_storage_sizes : s if s >= each.value.storage_gb][0] * 1024
  administrator_login           = "dbadmin"
  administrator_password        = random_password.databases[each.key].result
  backup_retention_days         = each.value.backup_retention_days
  public_network_access_enabled = false
  tags                          = local.tags

  dynamic "high_availability" {
    for_each = each.value.high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  lifecycle {
    ignore_changes = [zone, high_availability[0].standby_availability_zone]

    precondition {
      condition     = !each.value.high_availability || each.value.size != "small"
      error_message = "Azure: high_availability needs size medium or large (burstable SKUs do not support HA)."
    }
  }
}

resource "azurerm_mysql_flexible_server" "this" {
  for_each = local.mysql_dbs

  name                   = "mysql-${local.name_prefix}-${each.key}-${local.suffix}"
  location               = var.region
  resource_group_name    = local.resource_group_name
  version                = each.value.version == "8.0" ? "8.0.21" : each.value.version
  sku_name               = local.db_skus.mysql[each.value.size]
  administrator_login    = "dbadmin"
  administrator_password = random_password.databases[each.key].result
  backup_retention_days  = each.value.backup_retention_days
  public_network_access  = "Disabled"
  tags                   = local.tags

  storage {
    size_gb           = each.value.storage_gb
    auto_grow_enabled = true
  }

  dynamic "high_availability" {
    for_each = each.value.high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  lifecycle {
    ignore_changes = [zone, high_availability[0].standby_availability_zone]

    precondition {
      condition     = !each.value.high_availability || each.value.size != "small"
      error_message = "Azure: high_availability needs size medium or large (burstable SKUs do not support HA)."
    }
  }
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = local.postgres_dbs

  name      = each.value.db_name
  server_id = azurerm_postgresql_flexible_server.this[each.key].id
}

resource "azurerm_mysql_flexible_database" "this" {
  for_each = local.mysql_dbs

  name                = each.value.db_name
  resource_group_name = local.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this[each.key].name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

resource "azurerm_private_endpoint" "databases" {
  for_each = local.databases

  name                = "pe-${local.name_prefix}-${each.key}"
  location            = var.region
  resource_group_name = local.resource_group_name
  subnet_id           = local.db_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "${local.name_prefix}-${each.key}"
    private_connection_resource_id = each.value.engine == "postgres" ? azurerm_postgresql_flexible_server.this[each.key].id : azurerm_mysql_flexible_server.this[each.key].id
    subresource_names              = [each.value.engine == "postgres" ? "postgresqlServer" : "mysqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.databases[each.value.engine].id]
  }
}

resource "azurerm_key_vault_secret" "databases" {
  for_each = local.databases

  name         = "${each.key}-admin-password"
  value        = random_password.databases[each.key].result
  key_vault_id = azurerm_key_vault.this[0].id
  content_type = "password"
  tags         = local.tags

  depends_on = [time_sleep.key_vault_rbac]
}
