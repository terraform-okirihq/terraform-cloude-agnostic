locals {
  db_instance_classes = {
    small  = "db.t4g.small"
    medium = "db.m7g.large"
    large  = "db.m7g.xlarge"
  }

  create_databases = length(local.databases) > 0

  # RDS subnet groups need two AZs: use the private subnets if they span two,
  # otherwise fall back to every subnet (instances are never publicly accessible).
  private_db_azs = distinct([for k in local.private_subnet_keys : local.subnet_az[k]])
  db_subnet_keys = length(local.private_db_azs) >= 2 ? local.private_subnet_keys : sort(keys(local.subnets))

  db_log_exports = {
    postgres = ["postgresql", "upgrade"]
    mysql    = ["error", "slowquery"]
  }
}

resource "aws_db_subnet_group" "this" {
  count = local.create_databases ? 1 : 0

  region     = var.region
  name       = local.name_prefix
  subnet_ids = [for k in local.db_subnet_keys : aws_subnet.this[k].id]
  tags       = local.tags
}

resource "aws_security_group" "databases" {
  count = local.create_databases ? 1 : 0

  region      = var.region
  name        = "${local.name_prefix}-databases"
  description = "Databases: reachable only from inside the VPC"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${local.name_prefix}-databases" })
}

resource "aws_vpc_security_group_ingress_rule" "databases" {
  for_each = local.create_databases ? toset([for d in values(local.databases) : tostring(d.port)]) : toset([])

  region            = var.region
  security_group_id = aws_security_group.databases[0].id
  description       = "Database port from inside the VPC"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  cidr_ipv4         = var.network_cidr
}

resource "aws_db_instance" "this" {
  for_each = local.databases

  region                              = var.region
  identifier                          = "${local.name_prefix}-${each.key}"
  engine                              = each.value.engine
  engine_version                      = each.value.version
  instance_class                      = local.db_instance_classes[each.value.size]
  port                                = each.value.port
  allocated_storage                   = each.value.storage_gb
  max_allocated_storage               = each.value.storage_gb * 4
  storage_type                        = "gp3"
  storage_encrypted                   = true
  kms_key_id                          = local.kms_key_arn
  db_name                             = each.value.db_name
  username                            = "dbadmin"
  manage_master_user_password         = true # password lives in Secrets Manager
  master_user_secret_kms_key_id       = local.kms_key_arn
  iam_database_authentication_enabled = true
  multi_az                            = each.value.high_availability
  db_subnet_group_name                = aws_db_subnet_group.this[0].name
  vpc_security_group_ids              = [aws_security_group.databases[0].id]
  publicly_accessible                 = false
  backup_retention_period             = each.value.backup_retention_days
  copy_tags_to_snapshot               = true
  auto_minor_version_upgrade          = true
  enabled_cloudwatch_logs_exports     = local.db_log_exports[each.value.engine]
  deletion_protection                 = local.deletion_protection
  skip_final_snapshot                 = !local.deletion_protection
  final_snapshot_identifier           = local.deletion_protection ? "${local.name_prefix}-${each.key}-final" : null
  tags                                = local.tags
}
