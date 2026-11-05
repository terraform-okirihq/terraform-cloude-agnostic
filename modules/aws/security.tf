# Lock down the VPC's default security group (CIS AWS 5.4): no rules at all.
resource "aws_default_security_group" "this" {
  region = var.region
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-default-deny" })
}

resource "aws_security_group" "servers" {
  region      = var.region
  name        = "${local.name_prefix}-servers"
  description = "Servers managed by the multicloud foundation module"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${local.name_prefix}-servers" })
}

resource "aws_vpc_security_group_ingress_rule" "internal" {
  region            = var.region
  security_group_id = aws_security_group.servers.id
  description       = "All traffic from inside the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.network_cidr
}

resource "aws_vpc_security_group_ingress_rule" "custom" {
  for_each = {
    for pair in flatten([
      for r in local.ingress_rules : [
        for cidr in r.source_cidrs : { key = "${r.name}|${cidr}", rule = r, cidr = cidr }
      ]
    ]) : pair.key => pair
  }

  region            = var.region
  security_group_id = aws_security_group.servers.id
  description       = each.value.rule.name
  ip_protocol       = each.value.rule.protocol
  from_port         = each.value.rule.from_port
  to_port           = each.value.rule.to_port
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_egress_rule" "all" {
  region            = var.region
  security_group_id = aws_security_group.servers.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Customer-managed encryption key ----------------------------------------

data "aws_caller_identity" "current" {}

# Key policies must use Resource "*" (it refers to the key itself).
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:KMS key policy; Resource "*" means this key only
  #checkov:skip=CKV_AWS_111:KMS key policy; Resource "*" means this key only
  #checkov:skip=CKV_AWS_356:KMS key policy; Resource "*" means this key only
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  # CloudWatch alarms publish to the encrypted SNS alert topic.
  statement {
    sid       = "CloudWatchAlarmsToSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "this" {
  count = local.security.customer_managed_keys ? 1 : 0

  region                  = var.region
  description             = "${local.name_prefix} data encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  count = local.security.customer_managed_keys ? 1 : 0

  region        = var.region
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.this[0].key_id
}

locals {
  kms_key_arn = one(aws_kms_key.this[*].arn)
}

# --- VPC flow logs -----------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.security.flow_logs ? 1 : 0

  region            = var.region
  name              = "/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = local.monitoring.log_retention_days
  kms_key_id        = local.kms_key_arn
  tags              = local.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = local.security.flow_logs ? 1 : 0

  name               = "${local.name_prefix}-${var.region}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = local.security.flow_logs ? 1 : 0

  name = "write-flow-logs"
  role = aws_iam_role.flow_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = local.security.flow_logs ? 1 : 0

  region          = var.region
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  tags            = merge(local.tags, { Name = "${local.name_prefix}-flow-logs" })
}

# --- Security group for platform workloads (containers, functions) ----------

resource "aws_security_group" "workloads" {
  region      = var.region
  name        = "${local.name_prefix}-workloads"
  description = "Containers and functions managed by the multicloud foundation module"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${local.name_prefix}-workloads" })
}

resource "aws_vpc_security_group_ingress_rule" "workloads_internal" {
  region            = var.region
  security_group_id = aws_security_group.workloads.id
  description       = "All traffic from inside the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.network_cidr
}

resource "aws_vpc_security_group_egress_rule" "workloads_all" {
  region            = var.region
  security_group_id = aws_security_group.workloads.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
