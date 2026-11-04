module "context" {
  source = "../context"

  name           = var.name
  environment    = var.environment
  network_cidr   = var.network_cidr
  subnets        = var.subnets
  tags           = var.tags
  ingress_rules  = var.ingress_rules
  servers        = var.servers
  admin_username = var.admin_username
  ssh_public_key = var.ssh_public_key

  kubernetes          = var.kubernetes
  databases           = var.databases
  containers          = var.containers
  functions           = var.functions
  security            = var.security # accepted for interface parity; not used on Azure yet
  monitoring          = var.monitoring
  deletion_protection = var.deletion_protection
}

locals {
  name_prefix   = module.context.name_prefix
  subnets       = module.context.subnets
  tags          = module.context.tags
  ingress_rules = module.context.ingress_rules
  servers       = module.context.servers

  private_subnets = { for k, s in local.subnets : k => s if !s.public }
}
