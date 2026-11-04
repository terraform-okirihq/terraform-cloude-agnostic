mock_provider "google" {
  source = "./tests/mocks/google"
}

mock_provider "random" {}

variables {
  # Throwaway test-only public key; its private key was never kept.
  test_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDeNqobvAuJ4UXMGksAhTzBZv2zV3D19S3BPYhne8MQ6McHIBkGXprUeh2r7IjOmqAENp10hGuqe6pjKiRxngBHcBOfQQ452BCCVhQd/BfWrsOEmP7qjntmRyX5biRBVrY1nLz9IN800k7uUlhLpOScNLuOeKudIXFsxYYocmE9ECmt3HbQcokJp3TDUoFIaF5mLcwK4rzyw37eC1MyFgwhQGEgFzkdVdLABcxDf7MdP3pdfXfKnO8Izl2kc91EHlI+x206r0/vI0q7mC89E+cXYGhRuab02odNvWq66gW6HpT3dUPpwA4EUrDOeS/dJfP4KjtVRn7B03d7B7u7aPnp test-only@example"
  name                = "acme"
  environment         = "dev"
  region              = "europe-west1"
  project_id          = "acme-dev-123"
  tags                = { "Cost-Center" = "R&D" }
}

run "network_and_storage_defaults" {
  module {
    source = "./modules/gcp"
  }

  assert {
    condition     = output.network_name == "acme-dev-vpc" && length(output.subnet_ids) == 2
    error_message = "Unexpected VPC/subnets."
  }

  assert {
    condition     = output.storage_bucket_name != null
    error_message = "Bucket should be created."
  }

  assert {
    condition     = output.nat_public_ip == "203.0.113.40" && length(google_compute_router_nat.this) == 1
    error_message = "Cloud NAT with a static IP should be created by default."
  }

  assert {
    condition     = google_storage_bucket.this[0].labels["cost-center"] == "r_d"
    error_message = "Tags should be sanitised into valid GCP labels."
  }
}

run "servers_and_firewall" {
  module {
    source = "./modules/gcp"
  }

  variables {
    ssh_public_key = var.test_ssh_public_key
    ingress_rules  = [{ name = "app", from_port = 8000, to_port = 8080, source_cidrs = ["10.1.0.0/16"] }]
    servers = {
      web = { subnet = "public", size = "medium", public_ip = true }
      api = {}
      job = { size = "n2-highmem-2" }
    }
  }

  assert {
    condition     = google_compute_instance.server["web"].machine_type == "e2-standard-2" && google_compute_instance.server["job"].machine_type == "n2-highmem-2"
    error_message = "Sizes not mapped / passed through."
  }

  assert {
    condition     = google_compute_instance.server["api"].zone == "europe-west1-b" && google_compute_instance.server["job"].zone == "europe-west1-c" && google_compute_instance.server["web"].zone == "europe-west1-d"
    error_message = "Servers should be spread across available zones."
  }

  assert {
    condition     = one(google_compute_firewall.custom["app"].allow).ports[0] == "8000-8080"
    error_message = "Firewall port range not translated."
  }

  assert {
    condition     = google_compute_instance.server["web"].shielded_instance_config[0].enable_secure_boot
    error_message = "Servers must be Shielded VMs."
  }

  assert {
    condition     = output.servers["web"].public_ip == "203.0.113.50" && output.servers["api"].public_ip == null
    error_message = "Only servers with public_ip = true should expose a public IP."
  }
}
