# Private subnets have default outbound access disabled, so they need a NAT
# gateway (with a static public IP) to reach the internet.
locals {
  create_nat = var.enable_nat_gateway && length(local.private_subnets) > 0
}

resource "azurerm_public_ip" "nat" {
  count = local.create_nat ? 1 : 0

  name                = "pip-${local.name_prefix}-nat"
  location            = var.region
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  count = local.create_nat ? 1 : 0

  name                    = "ng-${local.name_prefix}"
  location                = var.region
  resource_group_name     = local.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = local.create_nat ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each = local.create_nat ? local.private_subnets : {}

  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}
