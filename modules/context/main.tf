# Provider-free module holding the cloud-agnostic conventions (naming,
# environment resolution, default subnets, tags). Every cloud module calls it
# so behaviour is identical across clouds.

locals {
  # Workspace names can contain characters that are invalid in resource names
  # (e.g. "Team_Prod"), so normalise them before use.
  workspace_environment = trim(substr(lower(replace(terraform.workspace, "/[^a-zA-Z0-9]+/", "-")), 0, 16), "-")

  environment = coalesce(var.environment, local.workspace_environment)

  # Two of each tier so AWS services that need two AZs (EKS, RDS, ALB) work
  # out of the box.
  subnets = var.subnets != null ? var.subnets : {
    public-a  = { cidr = cidrsubnet(var.network_cidr, 8, 0), public = true }
    public-b  = { cidr = cidrsubnet(var.network_cidr, 8, 1), public = true }
    private-a = { cidr = cidrsubnet(var.network_cidr, 8, 10), public = false }
    private-b = { cidr = cidrsubnet(var.network_cidr, 8, 11), public = false }
  }

  private_subnet_keys = sort([for k, s in local.subnets : k if !s.public])
  public_subnet_keys  = sort([for k, s in local.subnets : k if s.public])

  # Default placement for workloads: first private subnet, else first subnet.
  default_subnet = try(local.private_subnet_keys[0], sort(keys(local.subnets))[0])

  servers = {
    for k, s in var.servers : k => merge(s, { subnet = coalesce(s.subnet, local.default_subnet) })
  }

  kubernetes = merge(var.kubernetes, {
    subnets = coalesce(var.kubernetes.subnets, length(local.private_subnet_keys) > 0 ? local.private_subnet_keys : sort(keys(local.subnets)))
  })
}
