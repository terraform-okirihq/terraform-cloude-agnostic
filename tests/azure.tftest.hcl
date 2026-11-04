mock_provider "azurerm" {
  source = "./tests/mocks/azurerm"
}

mock_provider "random" {}

variables {
  # Throwaway test-only public key; its private key was never kept.
  test_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDeNqobvAuJ4UXMGksAhTzBZv2zV3D19S3BPYhne8MQ6McHIBkGXprUeh2r7IjOmqAENp10hGuqe6pjKiRxngBHcBOfQQ452BCCVhQd/BfWrsOEmP7qjntmRyX5biRBVrY1nLz9IN800k7uUlhLpOScNLuOeKudIXFsxYYocmE9ECmt3HbQcokJp3TDUoFIaF5mLcwK4rzyw37eC1MyFgwhQGEgFzkdVdLABcxDf7MdP3pdfXfKnO8Izl2kc91EHlI+x206r0/vI0q7mC89E+cXYGhRuab02odNvWq66gW6HpT3dUPpwA4EUrDOeS/dJfP4KjtVRn7B03d7B7u7aPnp test-only@example"
  name                = "acme-platform"
  environment         = "prod"
  region              = "westeurope"
}

run "network_and_storage_defaults" {
  module {
    source = "./modules/azure"
  }

  assert {
    condition     = output.resource_group_name == "rg-acme-platform-prod" && output.network_name == "vnet-acme-platform-prod"
    error_message = "Unexpected resource group or VNet name."
  }

  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", output.storage_bucket_name))
    error_message = "Storage account name violates Azure naming rules."
  }

  assert {
    condition     = output.nat_public_ip == "203.0.113.30" && length(azurerm_subnet_nat_gateway_association.this) == 1
    error_message = "NAT gateway should be attached to the private subnet only."
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 2
    error_message = "NSG should be attached to every subnet."
  }
}

run "servers_and_firewall" {
  module {
    source = "./modules/azure"
  }

  variables {
    resource_group_name = "rg-shared"
    ssh_public_key      = var.test_ssh_public_key
    ingress_rules       = [{ name = "https", from_port = 443, source_cidrs = ["0.0.0.0/0"] }]
    servers = {
      web = { subnet = "public", size = "large", public_ip = true }
      api = { image = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" }
    }
  }

  assert {
    condition     = output.resource_group_name == "rg-shared"
    error_message = "Existing resource group was not used."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.server["web"].size == "Standard_D4s_v5" && azurerm_linux_virtual_machine.server["api"].size == "Standard_B2s"
    error_message = "Portable sizes not mapped to Azure VM sizes."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.server["api"].source_image_reference[0].offer == "0001-com-ubuntu-server-jammy"
    error_message = "Custom image not parsed."
  }

  assert {
    condition     = azurerm_network_security_rule.custom["https"].destination_port_range == "443" && azurerm_network_security_rule.custom["https"].protocol == "Tcp"
    error_message = "NSG rule not translated correctly."
  }

  assert {
    condition     = output.servers["web"].public_ip == "203.0.113.30" && output.servers["api"].public_ip == null
    error_message = "Only servers with public_ip = true should expose a public IP."
  }
}

run "servers_require_ssh_key" {
  command = plan
  module {
    source = "./modules/azure"
  }

  variables {
    servers = { api = {} }
  }

  expect_failures = [azurerm_linux_virtual_machine.server]
}
