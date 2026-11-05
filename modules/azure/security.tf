# One NSG on every subnet. Azure's built-in rules already allow VNet-internal
# traffic and deny other inbound traffic; custom rules come from ingress_rules.
resource "azurerm_network_security_group" "this" {
  name                = "nsg-${local.name_prefix}"
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "custom" {
  for_each = { for i, r in local.ingress_rules : r.name => merge(r, { priority = 200 + i * 10 }) }

  name                        = each.key
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = title(each.value.protocol)
  source_port_range           = "*"
  destination_port_range      = each.value.port_range
  source_address_prefixes     = each.value.source_cidrs
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = local.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this.id
}

# --- Key Vault for generated secrets (database passwords) --------------------
# azurerm 5 uses Azure RBAC for Key Vault, so the identity running Terraform is
# granted "Key Vault Secrets Officer" on the vault it creates.

data "azurerm_client_config" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix           = random_id.suffix.hex
  create_key_vault = length(local.databases) > 0
}

resource "azurerm_key_vault" "this" {
  count = local.create_key_vault ? 1 : 0

  name                       = "kv-${substr(local.storage_prefix, 0, 13)}${local.suffix}"
  location                   = var.region
  resource_group_name        = local.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = local.deletion_protection
  soft_delete_retention_days = 30
  tags                       = local.tags
}

resource "azurerm_role_assignment" "key_vault_deployer" {
  count = local.create_key_vault ? 1 : 0

  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role assignments take a short while to propagate before secrets can be written.
resource "time_sleep" "key_vault_rbac" {
  count = local.create_key_vault ? 1 : 0

  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.key_vault_deployer]
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count = local.create_key_vault ? 1 : 0

  name                       = "audit-to-log-analytics"
  target_resource_id         = azurerm_key_vault.this[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }
}
