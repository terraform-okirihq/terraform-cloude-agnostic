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
  description = "Map of subnet key => { cidr, public }. When null, one public and one private /24 are derived from network_cidr."
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
    subnet       = optional(string, "private")
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
      contains(var.subnets != null ? keys(var.subnets) : ["public", "private"], s.subnet)
    ])
    error_message = "Every server's subnet must be a key of var.subnets (default subnets: public, private)."
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
