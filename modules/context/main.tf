# Provider-free module holding the cloud-agnostic conventions (naming,
# environment resolution, default subnets, tags). Every cloud module calls it
# so behaviour is identical across clouds.

locals {
  # Workspace names can contain characters that are invalid in resource names
  # (e.g. "Team_Prod"), so normalise them before use.
  workspace_environment = trim(substr(lower(replace(terraform.workspace, "/[^a-zA-Z0-9]+/", "-")), 0, 16), "-")

  environment = coalesce(var.environment, local.workspace_environment)

  subnets = var.subnets != null ? var.subnets : {
    public  = { cidr = cidrsubnet(var.network_cidr, 8, 0), public = true }
    private = { cidr = cidrsubnet(var.network_cidr, 8, 10), public = false }
  }
}
