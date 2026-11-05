resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name_prefix}"
  location            = var.region
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = local.monitoring.log_retention_days
  tags                = local.tags
}

resource "azurerm_monitor_action_group" "alerts" {
  count = length(local.monitoring.alert_emails) > 0 ? 1 : 0

  name                = "ag-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  short_name          = substr(replace(local.name_prefix, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = toset(local.monitoring.alert_emails)
    content {
      name                    = "email-${index(local.monitoring.alert_emails, email_receiver.value)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

locals {
  action_group_ids = azurerm_monitor_action_group.alerts[*].id
}

resource "azurerm_monitor_metric_alert" "server_cpu" {
  for_each = local.servers

  name                = "${local.name_prefix}-${each.key}-cpu-high"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_virtual_machine.server[each.key].id]
  description         = "CPU above ${local.monitoring.cpu_alert_threshold}% on server ${each.key}"
  severity            = 2
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.monitoring.cpu_alert_threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "database_cpu" {
  for_each = local.databases

  name                = "${local.name_prefix}-${each.key}-db-cpu-high"
  resource_group_name = local.resource_group_name
  scopes              = [each.value.engine == "postgres" ? azurerm_postgresql_flexible_server.this[each.key].id : azurerm_mysql_flexible_server.this[each.key].id]
  description         = "CPU above ${local.monitoring.cpu_alert_threshold}% on database ${each.key}"
  severity            = 2
  tags                = local.tags

  criteria {
    metric_namespace = each.value.engine == "postgres" ? "Microsoft.DBforPostgreSQL/flexibleServers" : "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.monitoring.cpu_alert_threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "kubernetes_cpu" {
  count = local.k8s_enabled ? 1 : 0

  name                = "${local.name_prefix}-aks-node-cpu-high"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_kubernetes_cluster.this[0].id]
  description         = "Node CPU above ${local.monitoring.cpu_alert_threshold}% on the AKS cluster"
  severity            = 2
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.monitoring.cpu_alert_threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
