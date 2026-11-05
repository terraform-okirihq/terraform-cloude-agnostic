locals {
  k8s_enabled = local.kubernetes.enabled

  node_vm_sizes = {
    small  = "Standard_D2s_v5"
    medium = "Standard_D4s_v5"
    large  = "Standard_D8s_v5"
  }

  aks_subnet        = local.kubernetes.subnets[0]
  k8s_open_endpoint = contains(local.kubernetes.authorized_cidrs, "0.0.0.0/0")

  # Nodes egress through the NAT gateway when their subnet has one.
  aks_outbound_type = local.create_nat && contains(keys(local.private_subnets), local.aks_subnet) ? "userAssignedNATGateway" : "loadBalancer"
}

resource "azurerm_user_assigned_identity" "aks" {
  count = local.k8s_enabled ? 1 : 0

  name                = "id-${local.name_prefix}-aks"
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

# AKS needs to manage NICs/load balancers in the VNet it is attached to.
resource "azurerm_role_assignment" "aks_network" {
  count = local.k8s_enabled ? 1 : 0

  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  count = local.k8s_enabled ? 1 : 0

  name                      = "aks-${local.name_prefix}"
  location                  = var.region
  resource_group_name       = local.resource_group_name
  dns_prefix                = local.name_prefix
  kubernetes_version        = local.kubernetes.version
  sku_tier                  = "Standard"
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"
  private_cluster_enabled   = !local.kubernetes.public_endpoint
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true
  local_account_disabled    = true # Entra ID authentication only

  default_node_pool {
    name                        = "system"
    vm_size                     = lookup(local.node_vm_sizes, local.kubernetes.node_size, local.kubernetes.node_size)
    vnet_subnet_id              = azurerm_subnet.this[local.aks_subnet].id
    auto_scaling_enabled        = true
    min_count                   = local.kubernetes.node_min
    max_count                   = local.kubernetes.node_max
    os_disk_size_gb             = local.kubernetes.node_disk_gb
    max_pods                    = 110
    temporary_name_for_rotation = "systemtmp"
    tags                        = local.tags

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Node pools are managed explicitly (autoscaled), not by node auto-provisioning.
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[0].id]
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  dynamic "api_server_access_profile" {
    for_each = local.kubernetes.public_endpoint && !local.k8s_open_endpoint ? [1] : []
    content {
      authorized_ip_ranges = local.kubernetes.authorized_cidrs
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = local.kubernetes.pod_cidr
    service_cidr        = local.kubernetes.service_cidr
    dns_service_ip      = cidrhost(local.kubernetes.service_cidr, 10)
    outbound_type       = local.aks_outbound_type
    load_balancer_sku   = "standard"
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = local.tags

  depends_on = [azurerm_role_assignment.aks_network, azurerm_subnet_nat_gateway_association.this]
}

# Lets the identity running Terraform use kubectl on the cluster.
resource "azurerm_role_assignment" "aks_deployer_admin" {
  count = local.k8s_enabled ? 1 : 0

  scope                = azurerm_kubernetes_cluster.this[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
