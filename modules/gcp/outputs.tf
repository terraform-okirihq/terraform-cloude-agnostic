# This output contract is shared by every cloud submodule; keep them in sync.

output "network_id" {
  description = "VPC network ID."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet key => subnetwork ID."
  value       = { for k, s in google_compute_subnetwork.this : k => s.id }
}

output "subnet_cidrs" {
  description = "Map of subnet key => CIDR."
  value       = { for k, s in google_compute_subnetwork.this : k => s.ip_cidr_range }
}

output "storage_bucket_name" {
  description = "GCS bucket name."
  value       = one(google_storage_bucket.this[*].name)
}

output "storage_bucket_url" {
  description = "gs:// URL of the bucket."
  value       = one(google_storage_bucket.this[*].url)
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
    for k, i in google_compute_instance.server : k => {
      id         = i.id
      private_ip = i.network_interface[0].network_ip
      public_ip  = local.servers[k].public_ip ? i.network_interface[0].access_config[0].nat_ip : null
    }
  }
}

output "nat_public_ip" {
  description = "Static egress IP of Cloud NAT (null when NAT is disabled)."
  value       = one(google_compute_address.nat[*].address)
}
