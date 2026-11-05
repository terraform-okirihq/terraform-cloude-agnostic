# Cloud SQL on private IP through Private Service Access.
# Requires the servicenetworking.googleapis.com and sqladmin.googleapis.com APIs.
locals {
  db_tiers = {
    small  = "db-custom-1-3840"
    medium = "db-custom-2-7680"
    large  = "db-custom-4-15360"
  }
  create_databases = length(local.databases) > 0

  # Audit and diagnostic logging for PostgreSQL (CIS GCP 6.2).
  postgres_flags = {
    "log_checkpoints"         = "on"
    "log_connections"         = "on"
    "log_disconnections"      = "on"
    "log_lock_waits"          = "on"
    "log_hostname"            = "on"
    "log_min_messages"        = "error"
    "log_min_error_statement" = "error"
    "log_statement"           = "ddl"
    "cloudsql.enable_pgaudit" = "on"
    "pgaudit.log"             = "ddl,role"
  }
}

resource "google_compute_global_address" "private_services" {
  count = local.create_databases ? 1 : 0

  project       = var.project_id
  name          = "${local.name_prefix}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "this" {
  count = local.create_databases ? 1 : 0

  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services[0].name]
  deletion_policy         = "ABANDON"
}

resource "random_password" "databases" {
  for_each = local.databases

  length           = 32
  special          = true
  override_special = "!#%*-_=+"
}

resource "google_sql_database_instance" "this" {
  for_each = local.databases

  project             = var.project_id
  name                = "${local.name_prefix}-${each.key}-${local.suffix}" # names can't be reused for a week
  region              = var.region
  database_version    = each.value.engine == "postgres" ? "POSTGRES_${each.value.version}" : "MYSQL_${replace(each.value.version, ".", "_")}"
  deletion_protection = local.deletion_protection

  settings {
    tier                        = local.db_tiers[each.value.size]
    edition                     = "ENTERPRISE"
    availability_type           = each.value.high_availability ? "REGIONAL" : "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = each.value.storage_gb
    disk_autoresize             = true
    deletion_protection_enabled = local.deletion_protection
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.this.id
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = each.value.engine == "postgres"
      binary_log_enabled             = each.value.engine == "mysql"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = each.value.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    insights_config {
      query_insights_enabled = true
    }

    dynamic "database_flags" {
      for_each = each.value.engine == "postgres" ? local.postgres_flags : {}
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    maintenance_window {
      day  = 7
      hour = 3
    }
  }

  depends_on = [google_service_networking_connection.this]
}

resource "google_sql_database" "this" {
  for_each = local.databases

  project  = var.project_id
  name     = each.value.db_name
  instance = google_sql_database_instance.this[each.key].name
}

resource "google_sql_user" "admin" {
  for_each = local.databases

  project  = var.project_id
  name     = "dbadmin"
  instance = google_sql_database_instance.this[each.key].name
  password = random_password.databases[each.key].result
}

resource "google_secret_manager_secret" "databases" {
  for_each = local.databases

  project   = var.project_id
  secret_id = "${local.name_prefix}-${each.key}-db-password"
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "databases" {
  for_each = local.databases

  secret      = google_secret_manager_secret.databases[each.key].id
  secret_data = random_password.databases[each.key].result
}
