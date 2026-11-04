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

output "kubernetes" {
  description = "Kubernetes cluster: { name, id, endpoint, version, kubeconfig_command } (null when disabled)."
  value = local.k8s_enabled ? {
    name               = google_container_cluster.this[0].name
    id                 = google_container_cluster.this[0].id
    endpoint           = "https://${google_container_cluster.this[0].endpoint}"
    version            = google_container_cluster.this[0].master_version
    kubeconfig_command = "gcloud container clusters get-credentials ${google_container_cluster.this[0].name} --region ${var.region} --project ${var.project_id}"
  } : null
}

output "databases" {
  description = "Map of database key => { engine, endpoint, port, database, username, credentials_secret }."
  value = {
    for k, d in local.databases : k => {
      engine             = d.engine
      endpoint           = google_sql_database_instance.this[k].private_ip_address
      port               = d.port
      database           = d.db_name
      username           = "dbadmin"
      credentials_secret = google_secret_manager_secret.databases[k].id
    }
  }
}

output "containers" {
  description = "Map of container key => { url } (url is null for private services)."
  value = {
    for k, c in local.containers : k => {
      url = c.public ? google_cloud_run_v2_service.this[k].uri : null
    }
  }
}

output "functions" {
  description = "Map of function key => { name, url }."
  value = {
    for k, f in google_cloudfunctions2_function.this : k => {
      name = f.name
      url  = f.url
    }
  }
}

output "kms_key_id" {
  description = "Cloud KMS key ID (null unless security.customer_managed_keys)."
  value       = local.kms_key_id
}
