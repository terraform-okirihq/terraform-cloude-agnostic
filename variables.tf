# ---------------------------------------------------------------------------
# Core (cloud-agnostic) inputs
# ---------------------------------------------------------------------------

# NOTE: this root module switches between clouds at plan time, so Terraform
# requires a configured provider for ALL of aws, azurerm and google. If you
# target a single cloud, call modules/aws, modules/azure or modules/gcp
# directly instead - they share this exact interface and need one provider.

variable "cloud" {
  description = "Target cloud provider. One of: aws, azure, gcp."
  type        = string

  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud)
    error_message = "cloud must be one of: aws, azure, gcp."
  }
}

variable "name" {
  description = "Short workload name used as the prefix for every resource (lowercase letters, digits, hyphens; 3-20 chars)."
  type        = string

}

variable "environment" {
  description = <<-EOT
    Environment name (e.g. dev, staging, prod). When null (default) the current
    Terraform workspace name is used, so the module works unchanged with CLI
    workspaces. Set it explicitly in CI/CD pipelines or HCP Terraform, where
    workspace names are often longer than the environment name.
  EOT
  type        = string
  default     = null

}

variable "region" {
  description = "Region to deploy into: AWS region (us-east-1), Azure location (westeurope) or GCP region (europe-west1)."
  type        = string
}

variable "network_cidr" {
  description = "IPv4 CIDR block for the VPC / VNet. On GCP it is used only to validate and derive subnet ranges."
  type        = string
  default     = "10.0.0.0/16"

}

variable "subnets" {
  description = <<-EOT
    Map of subnets to create, keyed by a short name. `public = true` gives the
    subnet a route to the internet (AWS: IGW route; Azure: default outbound
    access; GCP: no Private Google Access restriction). When null, one public
    and one private /24 are derived from network_cidr.
  EOT
  type = map(object({
    cidr   = string
    public = optional(bool, false)
  }))
  default = null

}

variable "create_storage_bucket" {
  description = "Create an object storage bucket (S3 bucket / Azure storage account + container / GCS bucket)."
  type        = bool
  default     = true
}

variable "storage_force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects (AWS and GCP only)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags applied to every resource. On GCP they become labels (sanitised to GCP's label rules)."
  type        = map(string)
  default     = {}
}

variable "enable_nat_gateway" {
  description = "Give private subnets outbound internet access through a NAT gateway with a static public IP."
  type        = bool
  default     = true
}

variable "ingress_rules" {
  description = "Inbound firewall rules for servers: list of { name, protocol (tcp|udp), from_port, to_port, source_cidrs }. Traffic inside the network is always allowed."
  type = list(object({
    name         = string
    protocol     = optional(string, "tcp")
    from_port    = number
    to_port      = optional(number)
    source_cidrs = list(string)
  }))
  default = []
}

variable "servers" {
  description = "Map of servers (VMs): { subnet, size (small|medium|large or a native machine type), image, disk_size_gb, public_ip, user_data (cloud-init) }."
  type = map(object({
    subnet       = optional(string) # null = first private subnet
    size         = optional(string, "small")
    image        = optional(string)
    disk_size_gb = optional(number, 30)
    public_ip    = optional(bool, false)
    user_data    = optional(string)
  }))
  default = {}
}

variable "admin_username" {
  description = "Admin user created on servers."
  type        = string
  default     = "cloudadmin"
}

variable "ssh_public_key" {
  description = "SSH public key for admin_username on servers (required for servers on Azure)."
  type        = string
  default     = null
}

variable "kubernetes" {
  description = "Managed Kubernetes (EKS / AKS / GKE): { enabled, version, subnets, node_size (small|medium|large or native), node_min, node_max, node_disk_gb, public_endpoint, authorized_cidrs, pod_cidr, service_cidr }."
  type = object({
    enabled          = optional(bool, false)
    version          = optional(string)
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
}

variable "databases" {
  description = "Managed databases keyed by name: { engine (postgres|mysql), version, size (small|medium|large), storage_gb, high_availability, backup_retention_days }."
  type = map(object({
    engine                = optional(string, "postgres")
    version               = optional(string)
    size                  = optional(string, "small")
    storage_gb            = optional(number, 32)
    high_availability     = optional(bool, false)
    backup_retention_days = optional(number, 7)
  }))
  default = {}
}

variable "containers" {
  description = "Container services keyed by name: { image, port, size (small|medium|large), min_replicas, max_replicas, public, env }."
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
}

variable "functions" {
  description = "Serverless functions keyed by name: { source_dir, runtime (python3.11|python3.12|nodejs20|nodejs22), entry_point, memory_mb, timeout_seconds, public, env }."
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
}

variable "security" {
  description = "Security settings: { customer_managed_keys, flow_logs }."
  type = object({
    customer_managed_keys = optional(bool, false)
    flow_logs             = optional(bool, true)
  })
  default = {}
}

variable "monitoring" {
  description = "Monitoring settings: { alert_emails, log_retention_days (30|60|90|180|365), cpu_alert_threshold }."
  type = object({
    alert_emails        = optional(list(string), [])
    log_retention_days  = optional(number, 30)
    cpu_alert_threshold = optional(number, 80)
  })
  default = {}
}

variable "deletion_protection" {
  description = "Protect stateful resources (databases, clusters, Cloud Run) from deletion."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Cloud-specific settings (only read for the selected cloud)
# ---------------------------------------------------------------------------

variable "aws" {
  description = "AWS-only settings."
  type = object({
    availability_zones = optional(list(string))
  })
  default = {}
}

variable "azure" {
  description = "Azure-only settings. Leave resource_group_name null to have the module create one."
  type = object({
    resource_group_name      = optional(string)
    storage_replication_type = optional(string, "LRS")
  })
  default = {}
}

variable "gcp" {
  description = "GCP-only settings. project_id is required when cloud = \"gcp\"."
  type = object({
    project_id    = optional(string)
    storage_class = optional(string, "STANDARD")
  })
  default = {}

  validation {
    condition     = var.cloud != "gcp" || var.gcp.project_id != null
    error_message = "gcp.project_id is required when cloud = \"gcp\"."
  }
}
