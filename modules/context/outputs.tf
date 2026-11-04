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
  description = "Validated server map with subnet defaults resolved."
  value       = local.servers
}

output "private_subnet_keys" {
  description = "Sorted keys of private subnets."
  value       = local.private_subnet_keys
}

output "public_subnet_keys" {
  description = "Sorted keys of public subnets."
  value       = local.public_subnet_keys
}

output "default_subnet" {
  description = "Subnet used when a workload does not choose one."
  value       = local.default_subnet
}

output "kubernetes" {
  description = "Kubernetes settings with subnet defaults resolved."
  value       = local.kubernetes
}

output "databases" {
  description = "Validated database map with engine defaults resolved."
  value = {
    for k, d in var.databases : k => merge(d, {
      version = coalesce(d.version, d.engine == "postgres" ? "16" : "8.0")
      port    = d.engine == "postgres" ? 5432 : 3306
      db_name = replace(k, "-", "_")
    })
  }
}

output "containers" {
  description = "Validated container map with size resolved to cpu/memory."
  value = {
    for k, c in var.containers : k => merge(c, {
      cpu       = { small = 0.5, medium = 1, large = 2 }[c.size]
      memory_gb = { small = 1, medium = 2, large = 4 }[c.size]
    })
  }
}

output "functions" {
  description = "Validated function map with runtime family resolved."
  value = {
    for k, f in var.functions : k => merge(f, {
      language        = startswith(f.runtime, "python") ? "python" : "node"
      runtime_version = startswith(f.runtime, "python") ? trimprefix(f.runtime, "python") : trimprefix(f.runtime, "nodejs")
    })
  }
}

output "security" {
  description = "Security settings."
  value       = var.security
}

output "monitoring" {
  description = "Monitoring settings."
  value       = var.monitoring
}

output "deletion_protection" {
  description = "Whether stateful resources are protected from deletion."
  value       = var.deletion_protection
}

output "admin_username" {
  description = "Admin username for servers."
  value       = var.admin_username
}

output "ssh_public_key" {
  description = "Validated SSH public key (or null)."
  value       = var.ssh_public_key
}
