mock_provider "google" {
  source = "./tests/mocks/google"
}

mock_provider "random" {
  source = "./tests/mocks/random"
}

mock_provider "archive" {
  source = "./tests/mocks/archive"
}

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
    condition     = output.network_name == "acme-dev-vpc" && length(output.subnet_ids) == 4
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
      web = { subnet = "public-a", size = "medium", public_ip = true }
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

run "platform_services" {
  module {
    source = "./modules/gcp"
  }

  variables {
    kubernetes = { enabled = true, node_min = 1, node_max = 9, public_endpoint = false }
    databases = {
      app       = { engine = "postgres", size = "large", high_availability = true, backup_retention_days = 14 }
      analytics = { engine = "mysql" }
    }
    containers = {
      web    = { image = "nginx:1.27" }
      worker = { image = "busybox:1.36", public = false }
    }
    functions = {
      api = { source_dir = "./examples/platform/functions/hello", runtime = "python3.11", public = true }
    }
    security   = { customer_managed_keys = true }
    monitoring = { alert_emails = ["ops@example.com"] }
  }

  # Kubernetes
  assert {
    condition     = google_container_cluster.this[0].private_cluster_config[0].enable_private_nodes && google_container_cluster.this[0].private_cluster_config[0].enable_private_endpoint
    error_message = "GKE nodes must be private; endpoint private when public_endpoint = false."
  }
  assert {
    condition     = google_container_node_pool.default[0].autoscaling[0].total_max_node_count == 9 && google_container_node_pool.default[0].node_config[0].workload_metadata_config[0].mode == "GKE_METADATA"
    error_message = "Node pool autoscaling / workload identity not configured."
  }
  assert {
    condition     = length(google_compute_subnetwork.this["private-a"].secondary_ip_range) == 2 && length(google_compute_subnetwork.this["private-b"].secondary_ip_range) == 0
    error_message = "Pod/service ranges should be added only to the GKE subnet."
  }
  assert {
    condition     = length(google_container_cluster.this[0].database_encryption) == 1
    error_message = "Kubernetes secrets should be encrypted with the CMK."
  }

  # Databases
  assert {
    condition     = length([for f in google_sql_database_instance.this["app"].settings[0].database_flags : f if f.name == "cloudsql.enable_pgaudit" && f.value == "on"]) == 1 && length(google_sql_database_instance.this["analytics"].settings[0].database_flags) == 0
    error_message = "PostgreSQL must get audit/log flags; MySQL must not get PostgreSQL flags."
  }
  assert {
    condition     = google_sql_database_instance.this["app"].database_version == "POSTGRES_16" && google_sql_database_instance.this["analytics"].database_version == "MYSQL_8_0"
    error_message = "Database versions not mapped."
  }
  assert {
    condition     = google_sql_database_instance.this["app"].settings[0].availability_type == "REGIONAL" && google_sql_database_instance.this["app"].settings[0].tier == "db-custom-4-15360"
    error_message = "HA / tier not mapped."
  }
  assert {
    condition     = !google_sql_database_instance.this["app"].settings[0].ip_configuration[0].ipv4_enabled && google_sql_database_instance.this["app"].settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "Cloud SQL must be private-IP only with TLS enforced."
  }
  assert {
    condition     = length(google_secret_manager_secret_version.databases) == 2
    error_message = "Passwords must be stored in Secret Manager."
  }

  # Containers + functions
  assert {
    condition     = google_cloud_run_v2_service.this["web"].ingress == "INGRESS_TRAFFIC_ALL" && google_cloud_run_v2_service.this["worker"].ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY"
    error_message = "Cloud Run ingress must follow the public flag."
  }
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.public) == 1 && length(google_cloud_run_v2_service_iam_member.public_functions) == 1
    error_message = "Only public services/functions get allUsers invoker."
  }
  assert {
    condition     = google_cloudfunctions2_function.this["api"].build_config[0].runtime == "python311" && google_cloudfunctions2_function.this["api"].service_config[0].ingress_settings == "ALLOW_ALL"
    error_message = "Function runtime/ingress not mapped."
  }

  # Security + monitoring
  assert {
    condition     = length(google_compute_subnetwork.this["private-a"].log_config) == 1 && length(google_kms_crypto_key_iam_member.storage) == 1
    error_message = "Flow logs and CMEK for storage expected."
  }
  assert {
    condition     = length(google_monitoring_notification_channel.email) == 1 && contains(keys(google_monitoring_alert_policy.this), "database-cpu") && contains(keys(google_monitoring_alert_policy.this), "kubernetes-cpu")
    error_message = "Alert policies not wired."
  }
}
