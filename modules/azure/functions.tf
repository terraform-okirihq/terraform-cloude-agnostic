# Azure Functions on the Flex Consumption plan.
# Code layout follows the Azure Functions programming model for the language
# (python: function_app.py, node: src/functions/*.js) inside source_dir.
# entry_point is not used on Azure: functions are declared in code.
locals {
  create_functions = length(local.functions) > 0

  # Flex Consumption instance sizes (MB).
  function_memory_sizes = [512, 2048, 4096]
}

data "archive_file" "functions" {
  for_each = local.functions

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.root}/.terraform/functions/${local.name_prefix}-${each.key}.zip"
}

resource "azurerm_storage_account" "functions" {
  count = local.create_functions ? 1 : 0

  name                            = "fn${substr(local.storage_prefix, 0, 14)}${local.suffix}"
  resource_group_name             = local.resource_group_name
  location                        = var.region
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "functions" {
  count = local.create_functions ? 1 : 0

  name                  = "deployments"
  storage_account_id    = azurerm_storage_account.functions[0].id
  container_access_type = "private"
}

resource "azurerm_service_plan" "functions" {
  count = local.create_functions ? 1 : 0

  name                = "asp-${local.name_prefix}"
  location            = var.region
  resource_group_name = local.resource_group_name
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.tags
}

resource "azurerm_application_insights" "functions" {
  count = local.create_functions ? 1 : 0

  name                = "appi-${local.name_prefix}"
  location            = var.region
  resource_group_name = local.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}

resource "azurerm_function_app_flex_consumption" "this" {
  for_each = local.functions

  name                        = trim(substr("func-${local.name_prefix}-${each.key}-${local.suffix}", 0, 60), "-")
  location                    = var.region
  resource_group_name         = local.resource_group_name
  service_plan_id             = azurerm_service_plan.functions[0].id
  runtime_name                = each.value.language
  runtime_version             = each.value.runtime_version
  instance_memory_in_mb       = [for m in local.function_memory_sizes : m if m >= each.value.memory_mb][0]
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.functions[0].primary_blob_endpoint}${azurerm_storage_container.functions[0].name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.functions[0].primary_access_key
  zip_deploy_file             = data.archive_file.functions[each.key].output_path
  https_only                  = true
  app_settings                = merge(each.value.env, { FUNCTIONS_TIMEOUT_SECONDS = tostring(each.value.timeout_seconds) })
  tags                        = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.functions[0].connection_string
    minimum_tls_version                    = "1.2"
  }
}
