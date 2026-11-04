# ---------------------------------------------------------------------------
# Shared cloud-agnostic interface (identical in modules/aws, azure, gcp)
# Validation lives in modules/context.
# ---------------------------------------------------------------------------

variable "name" {
  description = "Short workload name used as the prefix for every resource (lowercase letters, digits, hyphens; 3-20 chars)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod). When null, the current Terraform workspace name is used."
  type        = string
  default     = null
}

variable "region" {
  description = "Region / location to deploy into."
  type        = string
}

variable "network_cidr" {
  description = "IPv4 CIDR block for the network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Map of subnet key => { cidr, public }. When null, one public and one private /24 are derived from network_cidr."
  type = map(object({
    cidr   = string
    public = optional(bool, false)
  }))
  default = null
}

variable "create_storage_bucket" {
  description = "Create an object storage bucket."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to every resource."
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
    subnet       = optional(string, "private")
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
  description = "SSH public key for admin_username on servers."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Cloud-specific inputs
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Existing resource group to deploy into. When null, a resource group named rg-<name_prefix> is created."
  type        = string
  default     = null
}

variable "storage_replication_type" {
  description = "Storage account replication: LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

