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
