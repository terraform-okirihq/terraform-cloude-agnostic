mock_provider "azurerm" {
  source = "./tests/mocks/azurerm"
}

mock_provider "random" {
  source = "./tests/mocks/random"
}

mock_provider "archive" {
  source = "./tests/mocks/archive"
}

mock_provider "time" {}

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
    condition     = output.nat_public_ip == "203.0.113.30" && length(azurerm_subnet_nat_gateway_association.this) == 2
    error_message = "NAT gateway should be attached to the private subnets only."
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 4
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
      web = { subnet = "public-a", size = "large", public_ip = true }
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

run "platform_services" {
  module {
    source = "./modules/azure"
  }

  variables {
    kubernetes = { enabled = true, node_size = "small", authorized_cidrs = ["203.0.113.0/24"] }
    databases = {
      app       = { engine = "postgres", size = "medium", storage_gb = 50, high_availability = true }
      analytics = { engine = "mysql" }
    }
    containers = {
      web    = { image = "nginx:1.27", size = "large" }
      worker = { image = "busybox:1.36", public = false, min_replicas = 0 }
    }
    functions = {
      api = { source_dir = "./examples/platform/functions/hello", memory_mb = 1024, public = true }
    }
    monitoring = { alert_emails = ["ops@example.com", "oncall@example.com"] }
  }

  # Kubernetes
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].local_account_disabled && azurerm_kubernetes_cluster.this[0].network_profile[0].network_plugin_mode == "overlay"
    error_message = "AKS must use Entra ID auth and overlay networking."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].network_profile[0].outbound_type == "userAssignedNATGateway" && azurerm_kubernetes_cluster.this[0].network_profile[0].dns_service_ip == "172.20.0.10"
    error_message = "AKS egress should use the NAT gateway; DNS IP derived from service_cidr."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].vm_size == "Standard_D2s_v5" && length(azurerm_kubernetes_cluster.this[0].api_server_access_profile) == 1
    error_message = "Node size or authorized IP ranges not applied."
  }

  # Databases
  assert {
    condition     = azurerm_postgresql_flexible_server.this["app"].storage_mb == 65536 && azurerm_postgresql_flexible_server.this["app"].sku_name == "GP_Standard_D2ds_v5"
    error_message = "Postgres storage should round up to an allowed size (64 GB) and size map to the GP SKU."
  }
  assert {
    condition     = !azurerm_postgresql_flexible_server.this["app"].public_network_access_enabled && azurerm_mysql_flexible_server.this["analytics"].public_network_access == "Disabled"
    error_message = "Databases must not be publicly reachable."
  }
  assert {
    condition     = azurerm_mysql_flexible_server.this["analytics"].version == "8.0.21" && length(azurerm_private_endpoint.databases) == 2 && length(azurerm_private_dns_zone.databases) == 2
    error_message = "MySQL version mapping or private endpoints wrong."
  }
  assert {
    condition     = length(azurerm_key_vault_secret.databases) == 2 && azurerm_key_vault.this[0].rbac_authorization_enabled && azurerm_key_vault.this[0].purge_protection_enabled
    error_message = "Passwords must be stored in an RBAC Key Vault with purge protection."
  }

  # Containers
  assert {
    condition     = azurerm_container_app.this["web"].template[0].container[0].cpu == 2 && azurerm_container_app.this["web"].template[0].container[0].memory == "4Gi"
    error_message = "Container size not mapped."
  }
  assert {
    condition     = azurerm_container_app.this["web"].ingress[0].external_enabled && !azurerm_container_app.this["worker"].ingress[0].external_enabled
    error_message = "Ingress exposure must follow the public flag."
  }

  # Functions
  assert {
    condition     = azurerm_function_app_flex_consumption.this["api"].runtime_name == "python" && azurerm_function_app_flex_consumption.this["api"].runtime_version == "3.12" && azurerm_function_app_flex_consumption.this["api"].instance_memory_in_mb == 2048
    error_message = "Function runtime or memory rounding wrong."
  }

  # Storage hardening
  assert {
    condition     = azurerm_storage_account.functions[0].infrastructure_encryption_enabled && azurerm_storage_account.functions[0].blob_properties[0].delete_retention_policy[0].days == 7 && azurerm_storage_account.functions[0].sas_policy[0].expiration_period == "1.00:00:00"
    error_message = "Storage accounts need infrastructure encryption and soft delete."
  }

  # Monitoring
  assert {
    condition     = length(azurerm_monitor_action_group.alerts[0].email_receiver) == 2 && length(azurerm_monitor_metric_alert.database_cpu) == 2 && length(azurerm_monitor_metric_alert.kubernetes_cpu) == 1
    error_message = "Alerts not wired."
  }
}

run "ha_requires_non_burstable_sku" {
  command = plan
  module {
    source = "./modules/azure"
  }

  variables {
    databases = { app = { high_availability = true } }
  }

  expect_failures = [azurerm_postgresql_flexible_server.this]
}
