# azurerm validates resource ID formats, so mocked IDs must look real.
mock_resource "azurerm_storage_account" {
  defaults = {
    id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/mock"
    primary_blob_endpoint = "https://mock.blob.core.windows.net/"
  }
}

mock_resource "azurerm_subnet" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet"
  }
}

mock_resource "azurerm_network_security_group" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg"
  }
}

mock_resource "azurerm_nat_gateway" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/natGateways/ng"
  }
}

mock_resource "azurerm_public_ip" {
  defaults = {
    id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip"
    ip_address = "203.0.113.30"
  }
}

mock_resource "azurerm_network_interface" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/nic"
  }
}

mock_resource "azurerm_linux_virtual_machine" {
  defaults = {
    id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm"
    private_ip_address = "10.0.10.6"
  }
}
