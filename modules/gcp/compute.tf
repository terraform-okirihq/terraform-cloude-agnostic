locals {
  # Portable size names -> GCP machine types. Any other value is passed through.
  machine_types = {
    small  = "e2-small"
    medium = "e2-standard-2"
    large  = "n2-standard-4"
  }

  default_image  = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  create_servers = length(local.servers) > 0

  # Spread servers across the region's zones (not every region has zone "a").
  zones       = local.create_servers ? sort(data.google_compute_zones.available[0].names) : []
  server_zone = { for i, k in sort(keys(local.servers)) : k => local.zones[i % length(local.zones)] }
}

data "google_compute_zones" "available" {
  count = local.create_servers ? 1 : 0

  project = var.project_id
  region  = var.region
  status  = "UP"
}

# Dedicated least-privilege identity instead of the default compute SA.
resource "google_service_account" "servers" {
  count = local.create_servers ? 1 : 0

  project      = var.project_id
  account_id   = "${local.sa_prefix}-vm"
  display_name = "Servers for ${local.name_prefix}"
}

resource "google_project_iam_member" "servers" {
  for_each = local.create_servers ? toset(["roles/logging.logWriter", "roles/monitoring.metricWriter"]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.servers[0].email}"
}

resource "google_compute_instance" "server" {
  for_each = local.servers

  project                   = var.project_id
  name                      = "${local.name_prefix}-${each.key}"
  zone                      = local.server_zone[each.key]
  machine_type              = lookup(local.machine_types, each.value.size, each.value.size)
  tags                      = [local.server_tag]
  labels                    = local.labels
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image  = coalesce(each.value.image, local.default_image)
      size   = each.value.disk_size_gb
      type   = "pd-balanced"
      labels = local.labels
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this[each.value.subnet].id

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {}
    }
  }

  # ssh-keys is ignored if OS Login is enforced on the project; in that case
  # grant roles/compute.osAdminLogin instead.
  metadata = merge(
    { "block-project-ssh-keys" = "true" },
    module.context.ssh_public_key != null ? { "ssh-keys" = "${var.admin_username}:${module.context.ssh_public_key}" } : {},
    each.value.user_data != null ? { "user-data" = each.value.user_data } : {},
  )

  service_account {
    email  = google_service_account.servers[0].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  depends_on = [google_project_iam_member.servers, google_compute_router_nat.this]
}
