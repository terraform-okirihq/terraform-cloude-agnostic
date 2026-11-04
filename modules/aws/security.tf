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
