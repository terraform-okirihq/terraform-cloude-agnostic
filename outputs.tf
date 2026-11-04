locals {
  # Only one submodule exists, so each concat() yields a single element.
  selected = {
    network_id          = one(concat(module.aws[*].network_id, module.azure[*].network_id, module.gcp[*].network_id))
    network_name        = one(concat(module.aws[*].network_name, module.azure[*].network_name, module.gcp[*].network_name))
    subnet_ids          = one(concat(module.aws[*].subnet_ids, module.azure[*].subnet_ids, module.gcp[*].subnet_ids))
    subnet_cidrs        = one(concat(module.aws[*].subnet_cidrs, module.azure[*].subnet_cidrs, module.gcp[*].subnet_cidrs))
    storage_bucket_name = one(concat(module.aws[*].storage_bucket_name, module.azure[*].storage_bucket_name, module.gcp[*].storage_bucket_name))
    storage_bucket_url  = one(concat(module.aws[*].storage_bucket_url, module.azure[*].storage_bucket_url, module.gcp[*].storage_bucket_url))
    environment         = one(concat(module.aws[*].environment, module.azure[*].environment, module.gcp[*].environment))
    name_prefix         = one(concat(module.aws[*].name_prefix, module.azure[*].name_prefix, module.gcp[*].name_prefix))
    servers             = one(concat(module.aws[*].servers, module.azure[*].servers, module.gcp[*].servers))
    nat_public_ip       = one(concat(module.aws[*].nat_public_ip, module.azure[*].nat_public_ip, module.gcp[*].nat_public_ip))
    tags                = one(concat(module.aws[*].tags, module.azure[*].tags, module.gcp[*].tags))
  }
}

output "cloud" {
  description = "The cloud this module deployed to."
  value       = var.cloud
}

output "environment" {
  description = "Resolved environment name (var.environment or the Terraform workspace)."
  value       = local.selected.environment
}

output "name_prefix" {
  description = "Prefix applied to all resource names (<name>-<environment>)."
  value       = local.selected.name_prefix
}

output "region" {
  description = "Region / location the resources were deployed to."
  value       = var.region
}

output "network_id" {
  description = "ID of the VPC (AWS/GCP) or VNet (Azure)."
  value       = local.selected.network_id
}

output "network_name" {
  description = "Name of the VPC / VNet."
  value       = local.selected.network_name
}

output "subnet_ids" {
  description = "Map of subnet key => subnet ID."
  value       = local.selected.subnet_ids
}

output "subnet_cidrs" {
  description = "Map of subnet key => CIDR block."
  value       = local.selected.subnet_cidrs
}

output "storage_bucket_name" {
  description = "Bucket name (S3 / GCS) or storage account name (Azure). Null when create_storage_bucket = false."
  value       = local.selected.storage_bucket_name
}

output "storage_bucket_url" {
  description = "s3://, gs:// or https:// blob container URL of the bucket. Null when create_storage_bucket = false."
  value       = local.selected.storage_bucket_url
}

output "servers" {
  description = "Map of server key => { id, private_ip, public_ip }."
  value       = local.selected.servers
}

output "nat_public_ip" {
  description = "Static egress IP of the NAT gateway (null when NAT is disabled)."
  value       = local.selected.nat_public_ip
}

output "tags" {
  description = "Effective tags applied to resources."
  value       = local.selected.tags
}

output "azure_resource_group_name" {
  description = "Azure only: resource group holding the resources. Null on other clouds."
  value       = one(module.azure[*].resource_group_name)
}
