resource "google_monitoring_notification_channel" "email" {
  for_each = toset(local.monitoring.alert_emails)

  project      = var.project_id
  display_name = "${local.name_prefix} alerts: ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }
}

locals {
  notification_channels = [for c in google_monitoring_notification_channel.email : c.id]
  cpu_threshold         = local.monitoring.cpu_alert_threshold / 100

  alert_policies = merge(
    length(local.servers) > 0 ? {
      server-cpu = {
        name   = "Server CPU above ${local.monitoring.cpu_alert_threshold}%"
        filter = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\" AND metadata.user_labels.workload = \"${local.labels["workload"]}\" AND metadata.user_labels.environment = \"${local.labels["environment"]}\""
        value  = local.cpu_threshold
      }
    } : {},
    length(local.databases) > 0 ? {
      database-cpu = {
        name   = "Database CPU above ${local.monitoring.cpu_alert_threshold}%"
        filter = "resource.type = \"cloudsql_database\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\" AND resource.labels.database_id = starts_with(\"${var.project_id}:${local.name_prefix}-\")"
        value  = local.cpu_threshold
      }
    } : {},
    local.k8s_enabled ? {
      kubernetes-cpu = {
        name   = "GKE node CPU above ${local.monitoring.cpu_alert_threshold}%"
        filter = "resource.type = \"k8s_node\" AND metric.type = \"kubernetes.io/node/cpu/allocatable_utilization\" AND resource.labels.cluster_name = \"${local.name_prefix}\""
        value  = local.cpu_threshold
      }
    } : {},
    length(local.containers) + length(local.functions) > 0 ? {
      http-5xx = {
        name   = "Cloud Run / Functions 5xx responses"
        filter = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\" AND resource.labels.service_name = starts_with(\"${local.name_prefix}-\")"
        value  = 0.1 # requests per second
      }
    } : {},
  )
}

resource "google_monitoring_alert_policy" "this" {
  for_each = local.alert_policies

  project               = var.project_id
  display_name          = "${local.name_prefix}: ${each.value.name}"
  combiner              = "OR"
  notification_channels = local.notification_channels
  user_labels           = local.labels

  conditions {
    display_name = each.value.name

    condition_threshold {
      filter          = each.value.filter
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.value
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = each.key == "http-5xx" ? "ALIGN_RATE" : "ALIGN_MEAN"
      }
    }
  }
}
