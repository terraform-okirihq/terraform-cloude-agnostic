locals {
  server_tag = "${local.name_prefix}-server"
}

# GCP VPCs deny ingress by default; allow traffic between subnets.
resource "google_compute_firewall" "internal" {
  project       = var.project_id
  name          = "${local.name_prefix}-allow-internal"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = [for s in values(local.subnets) : s.cidr]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "custom" {
  for_each = { for r in local.ingress_rules : r.name => r }

  project       = var.project_id
  name          = "${local.name_prefix}-${each.key}"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = each.value.source_cidrs
  target_tags   = [local.server_tag]

  allow {
    protocol = each.value.protocol
    ports    = [each.value.port_range]
  }
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix = random_id.suffix.hex
  # Service account IDs are limited to 30 characters.
  sa_prefix = trim(substr(local.name_prefix, 0, 25), "-")
}

# --- Customer-managed encryption keys (Cloud KMS) ----------------------------
# Note: Cloud KMS key rings cannot be deleted. Destroying and re-creating the
# module in the same project with the same name will fail on the key ring.

resource "google_kms_key_ring" "this" {
  count = local.security.customer_managed_keys ? 1 : 0

  project = var.project_id
  # Key rings can never be deleted; the suffix lets an environment be destroyed
  # and recreated in the same project.
  name     = "${local.name_prefix}-keyring-${local.suffix}"
  location = var.region
}

resource "google_kms_crypto_key" "this" {
  count = local.security.customer_managed_keys ? 1 : 0

  name            = "${local.name_prefix}-data"
  key_ring        = google_kms_key_ring.this[0].id
  rotation_period = "7776000s" # 90 days
  labels          = local.labels

  lifecycle {
    prevent_destroy = false
  }
}

locals {
  kms_key_id = one(google_kms_crypto_key.this[*].id)
}

data "google_storage_project_service_account" "this" {
  count   = local.security.customer_managed_keys ? 1 : 0
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "storage" {
  count = local.security.customer_managed_keys ? 1 : 0

  crypto_key_id = google_kms_crypto_key.this[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.this[0].email_address}"
}

resource "google_kms_crypto_key_iam_member" "gke" {
  count = local.security.customer_managed_keys && local.k8s_enabled ? 1 : 0

  crypto_key_id = google_kms_crypto_key.this[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@container-engine-robot.iam.gserviceaccount.com"
}

# --- Identity for Cloud Run services and functions ---------------------------

resource "google_service_account" "workloads" {
  count = length(local.containers) + length(local.functions) > 0 ? 1 : 0

  project      = var.project_id
  account_id   = "${local.sa_prefix}-run"
  display_name = "Containers and functions for ${local.name_prefix}"
}

resource "google_project_iam_member" "workloads" {
  for_each = length(local.containers) + length(local.functions) > 0 ? toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workloads[0].email}"
}
