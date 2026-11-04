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
