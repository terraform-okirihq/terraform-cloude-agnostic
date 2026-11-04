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
