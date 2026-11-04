mock_data "google_compute_zones" {
  defaults = {
    names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
  }
}

mock_resource "google_service_account" {
  defaults = {
    email = "acme-dev-vm@acme-dev-123.iam.gserviceaccount.com"
  }
}

mock_resource "google_compute_address" {
  defaults = {
    address   = "203.0.113.40"
    self_link = "https://www.googleapis.com/compute/v1/projects/acme-dev-123/regions/europe-west1/addresses/acme-dev-nat"
  }
}

mock_resource "google_compute_instance" {
  defaults = {
    # Nested blocks are mocked with one object applied to every block.
    network_interface = {
      network_ip    = "10.0.10.7"
      access_config = { nat_ip = "203.0.113.50" }
    }
  }
}
