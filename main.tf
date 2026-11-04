# Exactly one of these module calls is instantiated, selected by var.cloud.
# All cloud modules share the same input/output contract.

module "aws" {
  source = "./modules/aws"
  count  = var.cloud == "aws" ? 1 : 0

  name                  = var.name
  environment           = var.environment
  region                = var.region
  network_cidr          = var.network_cidr
  subnets               = var.subnets
  create_storage_bucket = var.create_storage_bucket
  tags                  = var.tags
  enable_nat_gateway    = var.enable_nat_gateway
  ingress_rules         = var.ingress_rules
  servers               = var.servers
  admin_username        = var.admin_username
  ssh_public_key        = var.ssh_public_key
  kubernetes            = var.kubernetes
  databases             = var.databases
  containers            = var.containers
  functions             = var.functions
  security              = var.security
  monitoring            = var.monitoring
  deletion_protection   = var.deletion_protection

  storage_force_destroy = var.storage_force_destroy
  availability_zones    = var.aws.availability_zones
}

module "azure" {
  source = "./modules/azure"
  count  = var.cloud == "azure" ? 1 : 0

  name                  = var.name
  environment           = var.environment
  region                = var.region
  network_cidr          = var.network_cidr
  subnets               = var.subnets
  create_storage_bucket = var.create_storage_bucket
  tags                  = var.tags
  enable_nat_gateway    = var.enable_nat_gateway
  ingress_rules         = var.ingress_rules
  servers               = var.servers
  admin_username        = var.admin_username
  ssh_public_key        = var.ssh_public_key
  kubernetes            = var.kubernetes
  databases             = var.databases
  containers            = var.containers
  functions             = var.functions
  security              = var.security
  monitoring            = var.monitoring
  deletion_protection   = var.deletion_protection

  resource_group_name      = var.azure.resource_group_name
  storage_replication_type = var.azure.storage_replication_type
}

module "gcp" {
  source = "./modules/gcp"
  count  = var.cloud == "gcp" ? 1 : 0

  name                  = var.name
  environment           = var.environment
  region                = var.region
  network_cidr          = var.network_cidr
  subnets               = var.subnets
  create_storage_bucket = var.create_storage_bucket
  tags                  = var.tags
  enable_nat_gateway    = var.enable_nat_gateway
  ingress_rules         = var.ingress_rules
  servers               = var.servers
  admin_username        = var.admin_username
  ssh_public_key        = var.ssh_public_key
  kubernetes            = var.kubernetes
  databases             = var.databases
  containers            = var.containers
  functions             = var.functions
  security              = var.security
  monitoring            = var.monitoring
  deletion_protection   = var.deletion_protection

  storage_force_destroy = var.storage_force_destroy
  project_id            = coalesce(var.gcp.project_id, "unset")
  storage_class         = var.gcp.storage_class
}
