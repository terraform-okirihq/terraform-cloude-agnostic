# Container Apps run in a managed environment wired to Log Analytics.
# Public services get an external HTTPS endpoint; private ones are reachable
# only from inside the environment.

resource "azurerm_container_app_environment" "this" {
  count = length(local.containers) > 0 ? 1 : 0

  name                       = "cae-${local.name_prefix}"
  location                   = var.region
  resource_group_name        = local.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = local.tags
}

resource "azurerm_container_app" "this" {
  for_each = local.containers

  name                         = trim(substr("${local.name_prefix}-${each.key}", 0, 32), "-")
  container_app_environment_id = azurerm_container_app_environment.this[0].id
  resource_group_name          = local.resource_group_name
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type = "SystemAssigned"
  }

  template {
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas

    container {
      name   = each.key
      image  = each.value.image
      cpu    = each.value.cpu
      memory = "${each.value.memory_gb}Gi"

      dynamic "env" {
        for_each = each.value.env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  ingress {
    external_enabled = each.value.public
    target_port      = each.value.port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
