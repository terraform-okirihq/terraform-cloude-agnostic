variable "name" {
  description = "Short workload name used as the prefix for every resource (lowercase letters, digits, hyphens; 3-20 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.name))
    error_message = "name must be 3-20 chars, start with a letter, end with a letter/digit, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment name. When null, the current Terraform workspace name is used."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z0-9][a-z0-9-]{0,14}[a-z0-9]$", var.environment))
    error_message = "environment must be 2-16 chars of lowercase letters, digits and hyphens."
  }
}

variable "network_cidr" {
  description = "IPv4 CIDR block for the network."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.network_cidr))
    error_message = "network_cidr must be a valid IPv4 CIDR block, e.g. 10.0.0.0/16."
  }
}

variable "subnets" {
  description = "Map of subnet key => { cidr, public }. When null, two public and two private /24s are derived from network_cidr (public-a/b, private-a/b)."
  type = map(object({
    cidr   = string
    public = optional(bool, false)
  }))
  default = null

  validation {
    condition = var.subnets == null || alltrue([
      for k, s in coalesce(var.subnets, {}) :
      can(cidrnetmask(s.cidr)) && can(regex("^[a-z][a-z0-9-]{0,20}$", k))
    ])
    error_message = "Each subnet key must be lowercase (a-z, 0-9, -, max 21 chars) and each cidr a valid IPv4 CIDR."
  }
}

variable "tags" {
  description = "Extra tags merged over the module's default tags."
  type        = map(string)
  default     = {}
}

variable "ingress_rules" {
  description = "Inbound firewall rules applied to servers. Traffic inside the network is always allowed."
  type = list(object({
    name         = string
    protocol     = optional(string, "tcp")
    from_port    = number
    to_port      = optional(number)
    source_cidrs = list(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.ingress_rules :
      can(regex("^[a-z][a-z0-9-]{0,19}$", r.name)) &&
      contains(["tcp", "udp"], r.protocol) &&
      r.from_port >= 1 &&
      coalesce(r.to_port, r.from_port) >= r.from_port &&
      coalesce(r.to_port, r.from_port) <= 65535 &&
      length(r.source_cidrs) > 0 &&
      alltrue([for c in r.source_cidrs : can(cidrnetmask(c))])
    ])
    error_message = "Each ingress rule needs a lowercase name (max 20 chars), protocol tcp|udp, ports within 1-65535 with from_port <= to_port, and at least one valid source CIDR."
  }

  validation {
    condition     = length(distinct([for r in var.ingress_rules : r.name])) == length(var.ingress_rules)
    error_message = "ingress_rules names must be unique."
  }
}

variable "servers" {
  description = "Map of servers (VMs) to create, keyed by a short name."
  type = map(object({
    subnet       = optional(string) # null = first private subnet
    size         = optional(string, "small")
    image        = optional(string)
    disk_size_gb = optional(number, 30)
    public_ip    = optional(bool, false)
    user_data    = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, s in var.servers :
      can(regex("^[a-z][a-z0-9-]{0,14}$", k)) && s.disk_size_gb >= 10 && s.disk_size_gb <= 4096
    ])
    error_message = "Server keys must be lowercase (a-z, 0-9, -, max 15 chars) and disk_size_gb between 10 and 4096."
  }

  validation {
    condition = alltrue([
      for s in values(var.servers) :
      s.subnet == null || contains(var.subnets != null ? keys(var.subnets) : ["public-a", "public-b", "private-a", "private-b"], coalesce(s.subnet, "-"))
    ])
    error_message = "Every server's subnet must be a key of var.subnets (default subnets: public-a, public-b, private-a, private-b)."
  }
}

variable "admin_username" {
  description = "Admin user created on servers."
  type        = string
  default     = "cloudadmin"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.admin_username)) && !contains(["admin", "administrator", "root", "user", "guest"], var.admin_username)
    error_message = "admin_username must be a valid Linux username and not a reserved name (admin, administrator, root, user, guest)."
  }
}

variable "ssh_public_key" {
  description = "SSH public key installed for admin_username on servers."
  type        = string
  default     = null

  validation {
    condition     = var.ssh_public_key == null || can(regex("^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521)) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-rsa, ssh-ed25519 or ecdsa-sha2-*)."
  }
}

# ---------------------------------------------------------------------------
# Platform services
# ---------------------------------------------------------------------------

variable "kubernetes" {
  description = "Managed Kubernetes (EKS / AKS / GKE)."
  type = object({
    enabled          = optional(bool, false)
    version          = optional(string) # null = cloud default
    subnets          = optional(list(string))
    node_size        = optional(string, "medium")
    node_min         = optional(number, 1)
    node_max         = optional(number, 3)
    node_disk_gb     = optional(number, 50)
    public_endpoint  = optional(bool, true)
    authorized_cidrs = optional(list(string), ["0.0.0.0/0"])
    pod_cidr         = optional(string, "100.64.0.0/16")
    service_cidr     = optional(string, "172.20.0.0/16")
  })
  default = {}

  validation {
    condition = (
      var.kubernetes.node_min >= 1 &&
      var.kubernetes.node_max >= var.kubernetes.node_min &&
      var.kubernetes.node_max <= 100 &&
      var.kubernetes.node_disk_gb >= 30 &&
      can(cidrnetmask(var.kubernetes.pod_cidr)) &&
      can(cidrnetmask(var.kubernetes.service_cidr)) &&
      alltrue([for c in var.kubernetes.authorized_cidrs : can(cidrnetmask(c))])
    )
    error_message = "kubernetes: need 1 <= node_min <= node_max <= 100, node_disk_gb >= 30, and valid CIDRs."
  }

  validation {
    condition = var.kubernetes.subnets == null || alltrue([
      for s in coalesce(var.kubernetes.subnets, []) :
      contains(var.subnets != null ? keys(var.subnets) : ["public-a", "public-b", "private-a", "private-b"], s)
    ])
    error_message = "kubernetes.subnets must be keys of var.subnets."
  }
}

variable "databases" {
  description = "Managed PostgreSQL / MySQL databases (RDS / Azure Flexible Server / Cloud SQL), keyed by name."
  type = map(object({
    engine                = optional(string, "postgres")
    version               = optional(string)
    size                  = optional(string, "small")
    storage_gb            = optional(number, 32)
    high_availability     = optional(bool, false)
    backup_retention_days = optional(number, 7)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, d in var.databases :
      can(regex("^[a-z][a-z0-9-]{0,14}$", k)) &&
      contains(["postgres", "mysql"], d.engine) &&
      contains(["small", "medium", "large"], d.size) &&
      d.storage_gb >= 20 && d.storage_gb <= 16384 &&
      d.backup_retention_days >= 7 && d.backup_retention_days <= 35
    ])
    error_message = "databases: lowercase keys (max 15 chars), engine postgres|mysql, size small|medium|large, storage_gb 20-16384, backup_retention_days 7-35."
  }
}

variable "containers" {
  description = "Containerised HTTP services (ECS Fargate / Azure Container Apps / Cloud Run), keyed by name."
  type = map(object({
    image        = string
    port         = optional(number, 80)
    size         = optional(string, "small")
    min_replicas = optional(number, 1)
    max_replicas = optional(number, 3)
    public       = optional(bool, true)
    env          = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, c in var.containers :
      can(regex("^[a-z][a-z0-9-]{0,14}$", k)) &&
      contains(["small", "medium", "large"], c.size) &&
      c.port >= 1 && c.port <= 65535 &&
      c.min_replicas >= 0 && c.max_replicas >= max(c.min_replicas, 1) && c.max_replicas <= 100
    ])
    error_message = "containers: lowercase keys (max 15 chars), size small|medium|large, valid port, 0 <= min_replicas <= max_replicas <= 100."
  }
}

variable "functions" {
  description = "Serverless functions (Lambda / Azure Functions / Cloud Functions), keyed by name."
  type = map(object({
    source_dir      = string
    runtime         = optional(string, "python3.12")
    entry_point     = optional(string, "handler")
    memory_mb       = optional(number, 512)
    timeout_seconds = optional(number, 60)
    public          = optional(bool, false)
    env             = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, f in var.functions :
      can(regex("^[a-z][a-z0-9-]{0,14}$", k)) &&
      contains(["python3.11", "python3.12", "nodejs20", "nodejs22"], f.runtime) &&
      can(regex("^[A-Za-z_][A-Za-z0-9_]*$", f.entry_point)) &&
      f.memory_mb >= 512 && f.memory_mb <= 4096 &&
      f.timeout_seconds >= 1 && f.timeout_seconds <= 540
    ])
    error_message = "functions: lowercase keys (max 15 chars), runtime python3.11|python3.12|nodejs20|nodejs22, valid entry_point, memory_mb 512-4096, timeout_seconds 1-540."
  }
}

variable "security" {
  description = "Security settings."
  type = object({
    customer_managed_keys = optional(bool, false)
    flow_logs             = optional(bool, true)
  })
  default = {}
}

variable "monitoring" {
  description = "Monitoring and alerting settings."
  type = object({
    alert_emails        = optional(list(string), [])
    log_retention_days  = optional(number, 30)
    cpu_alert_threshold = optional(number, 80)
  })
  default = {}

  validation {
    condition = (
      contains([30, 60, 90, 180, 365], var.monitoring.log_retention_days) &&
      var.monitoring.cpu_alert_threshold > 0 && var.monitoring.cpu_alert_threshold <= 100 &&
      alltrue([for e in var.monitoring.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    )
    error_message = "monitoring: log_retention_days one of 30|60|90|180|365, cpu_alert_threshold 1-100, alert_emails must be valid addresses."
  }
}

variable "deletion_protection" {
  description = "Protect stateful resources (databases, clusters, Cloud Run) from deletion."
  type        = bool
  default     = true
}
