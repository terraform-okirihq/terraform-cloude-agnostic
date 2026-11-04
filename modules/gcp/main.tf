locals {
  # GCP labels: lowercase letters, digits, _ and -; max 63 chars.
  labels = {
    for k, v in local.tags :
    substr(replace(lower(k), "/[^a-z0-9_-]/", "_"), 0, 63) => substr(replace(lower(v), "/[^a-z0-9_-]/", "_"), 0, 63)
  }
}

# --- Network ---------------------------------------------------------------
# GCP VPCs are global and have no address space of their own; the CIDR lives
# on the regional subnetworks. "public" subnets simply skip Private Google
# Access; internet egress for private instances needs Cloud NAT (not included).

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  for_each = local.subnets

  project                  = var.project_id
  name                     = "${local.name_prefix}-${each.key}"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = !each.value.public
}

# --- Storage ---------------------------------------------------------------

resource "random_id" "bucket" {
  count       = var.create_storage_bucket ? 1 : 0
  byte_length = 4
}

resource "google_storage_bucket" "this" {
  count = var.create_storage_bucket ? 1 : 0

  project                     = var.project_id
  name                        = "${local.name_prefix}-${random_id.bucket[0].hex}"
  location                    = upper(var.region)
  storage_class               = var.storage_class
  force_destroy               = var.storage_force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  labels = local.labels
}
