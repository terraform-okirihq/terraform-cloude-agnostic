# This output contract is shared by every cloud submodule; keep them in sync.

output "network_id" {
  description = "VNet ID."
  value       = azurerm_virtual_network.this.id
}

output "network_name" {
  description = "VNet name."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet key => subnet ID."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "subnet_cidrs" {
  description = "Map of subnet key => CIDR."
  value       = { for k, s in azurerm_subnet.this : k => s.address_prefixes[0] }
}

output "storage_bucket_name" {
  description = "Storage account name."
  value       = one(azurerm_storage_account.this[*].name)
}

output "storage_bucket_url" {
  description = "HTTPS URL of the private 'data' blob container."
  value       = var.create_storage_bucket ? "${azurerm_storage_account.this[0].primary_blob_endpoint}${azurerm_storage_container.this[0].name}" : null
}

# Azure-specific extra output.
output "resource_group_name" {
  description = "Resource group containing the resources."
  value       = local.resource_group_name
}

output "environment" {
  description = "Resolved environment name."
  value       = module.context.environment
}

output "name_prefix" {
  description = "Prefix applied to all resource names."
  value       = local.name_prefix
}

output "region" {
  description = "Region the resources were deployed to."
  value       = var.region
}

output "tags" {
  description = "Effective tags."
  value       = local.tags
}

output "servers" {
  description = "Map of server key => { id, private_ip, public_ip }."
  value = {
    for k, vm in azurerm_linux_virtual_machine.server : k => {
      id         = vm.id
      private_ip = vm.private_ip_address
      public_ip  = local.servers[k].public_ip ? azurerm_public_ip.server[k].ip_address : null
    }
  }
}

output "nat_public_ip" {
  description = "Static egress IP of the NAT gateway (null when NAT is disabled)."
  value       = one(azurerm_public_ip.nat[*].ip_address)
}

output "network_security_group_id" {
  description = "NSG associated with every subnet."
  value       = azurerm_network_security_group.this.id
}

output "kubernetes" {
  description = "Kubernetes cluster: { name, id, endpoint, version, kubeconfig_command } (null when disabled)."
  value = local.k8s_enabled ? {
    name               = azurerm_kubernetes_cluster.this[0].name
    id                 = azurerm_kubernetes_cluster.this[0].id
    endpoint           = "https://${coalesce(azurerm_kubernetes_cluster.this[0].fqdn, azurerm_kubernetes_cluster.this[0].private_fqdn)}"
    version            = azurerm_kubernetes_cluster.this[0].current_kubernetes_version
    kubeconfig_command = "az aks get-credentials --resource-group ${local.resource_group_name} --name ${azurerm_kubernetes_cluster.this[0].name} && kubelogin convert-kubeconfig -l azurecli"
  } : null
}

output "databases" {
  description = "Map of database key => { engine, endpoint, port, database, username, credentials_secret }."
  value = {
    for k, d in local.databases : k => {
      engine             = d.engine
      endpoint           = d.engine == "postgres" ? azurerm_postgresql_flexible_server.this[k].fqdn : azurerm_mysql_flexible_server.this[k].fqdn
      port               = d.port
      database           = d.db_name
      username           = "dbadmin"
      credentials_secret = azurerm_key_vault_secret.databases[k].versionless_id
    }
  }
}

output "containers" {
  description = "Map of container key => { url } (url is null for private services)."
  value = {
    for k, c in local.containers : k => {
      url = c.public ? "https://${azurerm_container_app.this[k].ingress[0].fqdn}" : null
    }
  }
}

output "functions" {
  description = "Map of function key => { name, url }."
  value = {
    for k, f in azurerm_function_app_flex_consumption.this : k => {
      name = f.name
      url  = "https://${f.default_hostname}"
    }
  }
}

output "kms_key_id" {
  description = "Customer-managed key ID. Always null on Azure: data uses Microsoft-managed keys."
  value       = null
}

output "key_vault_id" {
  description = "Key Vault holding generated secrets (null without databases)."
  value       = one(azurerm_key_vault.this[*].id)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}
