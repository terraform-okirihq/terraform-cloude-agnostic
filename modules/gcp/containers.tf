# Cloud Run services. Egress to private IPs (databases, VMs) goes through
# Direct VPC egress into the default private subnet.
locals {
  cloud_run_cpu = { small = "1", medium = "1", large = "2" }
}

resource "google_cloud_run_v2_service" "this" {
  for_each = local.containers

  project             = var.project_id
  name                = trim(substr("${local.name_prefix}-${each.key}", 0, 49), "-")
  location            = var.region
  ingress             = each.value.public ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = local.deletion_protection
  labels              = local.labels

  template {
    service_account = google_service_account.workloads[0].email

    scaling {
      min_instance_count = each.value.min_replicas
      max_instance_count = each.value.max_replicas
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = google_compute_network.this.id
        subnetwork = google_compute_subnetwork.this[local.default_subnet].id
      }
    }

    containers {
      image = each.value.image

      ports {
        container_port = each.value.port
      }

      resources {
        limits = {
          cpu    = local.cloud_run_cpu[each.value.size]
          memory = "${each.value.memory_gb}Gi"
        }
        cpu_idle = true
      }

      dynamic "env" {
        for_each = each.value.env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  depends_on = [google_project_iam_member.workloads]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  for_each = { for k, c in local.containers : k => c if c.public }

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this[each.key].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
