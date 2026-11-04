output "environment" {
  description = "Resolved environment (var.environment, else terraform.workspace)."
  value       = local.environment
}

output "name_prefix" {
  description = "<name>-<environment>."
  value       = "${var.name}-${local.environment}"
}

output "subnets" {
  description = "Effective subnet map."
  value       = local.subnets
}

output "tags" {
  description = "Default tags merged with var.tags."
  value = merge(
    {
      "managed-by"  = "terraform"
      "environment" = local.environment
      "workload"    = var.name
    },
    var.tags,
  )
}

output "ingress_rules" {
  description = "Ingress rules with to_port resolved and a port_range string (\"22\" or \"8000-8080\")."
  value = [
    for r in var.ingress_rules : {
      name         = r.name
      protocol     = r.protocol
      from_port    = r.from_port
      to_port      = coalesce(r.to_port, r.from_port)
      port_range   = coalesce(r.to_port, r.from_port) == r.from_port ? tostring(r.from_port) : "${r.from_port}-${r.to_port}"
      source_cidrs = r.source_cidrs
    }
  ]
}

output "servers" {
  description = "Validated server map."
  value       = var.servers
}

output "admin_username" {
  description = "Admin username for servers."
  value       = var.admin_username
}

output "ssh_public_key" {
  description = "Validated SSH public key (or null)."
  value       = var.ssh_public_key
}
