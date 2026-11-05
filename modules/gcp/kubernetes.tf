locals {
  k8s_enabled = local.kubernetes.enabled

  node_machine_types = {
    small  = "e2-standard-2"
    medium = "e2-standard-4"
    large  = "e2-standard-8"
  }

  gke_subnet        = local.kubernetes.subnets[0]
  k8s_open_endpoint = contains(local.kubernetes.authorized_cidrs, "0.0.0.0/0")
}

resource "google_service_account" "gke_nodes" {
  count = local.k8s_enabled ? 1 : 0

  project      = var.project_id
  account_id   = "${local.sa_prefix}-gke"
  display_name = "GKE nodes for ${local.name_prefix}"
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = local.k8s_enabled ? toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/autoscaling.metricsWriter",
    "roles/artifactregistry.reader",
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes[0].email}"
}

resource "google_container_cluster" "this" {
  count = local.k8s_enabled ? 1 : 0

  project               = var.project_id
  name                  = local.name_prefix
  location              = var.region # regional control plane
  network               = google_compute_network.this.id
  subnetwork            = google_compute_subnetwork.this[local.gke_subnet].id
  min_master_version    = local.kubernetes.version
  initial_node_count    = 0 # no default pool; nodes come from google_container_node_pool
  deletion_protection   = local.deletion_protection
  datapath_provider     = "ADVANCED_DATAPATH" # Dataplane V2 with network policy
  enable_shielded_nodes = true
  resource_labels       = local.labels

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = !local.kubernetes.public_endpoint
  }

  dynamic "master_authorized_networks_config" {
    for_each = local.k8s_open_endpoint ? [] : [1]
    content {
      dynamic "cidr_blocks" {
        for_each = local.kubernetes.authorized_cidrs
        content {
          cidr_block = cidr_blocks.value
        }
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  dynamic "database_encryption" {
    for_each = local.kms_key_id != null ? [1] : []
    content {
      state    = "ENCRYPTED"
      key_name = local.kms_key_id
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  depends_on = [google_project_iam_member.gke_nodes, google_kms_crypto_key_iam_member.gke, google_compute_router_nat.this]
}

resource "google_container_node_pool" "default" {
  count = local.k8s_enabled ? 1 : 0

  project  = var.project_id
  name     = "default"
  cluster  = google_container_cluster.this[0].id
  location = var.region

  autoscaling {
    total_min_node_count = local.kubernetes.node_min
    total_max_node_count = local.kubernetes.node_max
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = lookup(local.node_machine_types, local.kubernetes.node_size, local.kubernetes.node_size)
    disk_size_gb    = local.kubernetes.node_disk_gb
    disk_type       = "pd-balanced"
    service_account = google_service_account.gke_nodes[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = local.labels

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
