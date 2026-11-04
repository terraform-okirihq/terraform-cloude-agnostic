# Cloud NAT for private subnets, using a reserved static IP so egress can be
# allowlisted by third parties.
locals {
  create_nat = var.enable_nat_gateway && length(local.private_subnets) > 0
}

resource "google_compute_address" "nat" {
  count = local.create_nat ? 1 : 0

  project = var.project_id
  name    = "${local.name_prefix}-nat"
  region  = var.region
  labels  = local.labels
}

resource "google_compute_router" "this" {
  count = local.create_nat ? 1 : 0

  project = var.project_id
  name    = "${local.name_prefix}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  count = local.create_nat ? 1 : 0

  project                            = var.project_id
  name                               = "${local.name_prefix}-nat"
  router                             = google_compute_router.this[0].name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat[0].self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = local.private_subnets
    content {
      name                    = google_compute_subnetwork.this[subnetwork.key].id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
