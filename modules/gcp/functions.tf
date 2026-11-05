# Cloud Functions (2nd gen). Code layout (same as AWS):
#   python: <source_dir>/main.py  defining <entry_point>(request)
#   node:   <source_dir>/index.js exporting <entry_point>
locals {
  gcf_runtimes = {
    "python3.11" = "python311"
    "python3.12" = "python312"
    "nodejs20"   = "nodejs20"
    "nodejs22"   = "nodejs22"
  }
  create_functions = length(local.functions) > 0
}

data "archive_file" "functions" {
  for_each = local.functions

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.root}/.terraform/functions/${local.name_prefix}-${each.key}.zip"
}

resource "google_storage_bucket" "functions" {
  count = local.create_functions ? 1 : 0

  project                     = var.project_id
  name                        = "${local.name_prefix}-fn-${local.suffix}"
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # holds only build artifacts
  labels                      = local.labels

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_object" "functions" {
  for_each = local.functions

  name   = "${each.key}-${data.archive_file.functions[each.key].output_md5}.zip"
  bucket = google_storage_bucket.functions[0].name
  source = data.archive_file.functions[each.key].output_path
}

resource "google_cloudfunctions2_function" "this" {
  for_each = local.functions

  project  = var.project_id
  name     = trim(substr("${local.name_prefix}-${each.key}", 0, 63), "-")
  location = var.region
  labels   = local.labels

  build_config {
    runtime     = local.gcf_runtimes[each.value.runtime]
    entry_point = each.value.entry_point

    source {
      storage_source {
        bucket = google_storage_bucket.functions[0].name
        object = google_storage_bucket_object.functions[each.key].name
      }
    }
  }

  service_config {
    available_memory      = "${each.value.memory_mb}M"
    timeout_seconds       = each.value.timeout_seconds
    max_instance_count    = 100
    ingress_settings      = each.value.public ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"
    service_account_email = google_service_account.workloads[0].email
    environment_variables = each.value.env
  }

  depends_on = [google_project_iam_member.workloads]
}

# 2nd-gen functions are served by Cloud Run; public access is granted there.
resource "google_cloud_run_v2_service_iam_member" "public_functions" {
  for_each = { for k, f in local.functions : k => f if f.public }

  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.this[each.key].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
