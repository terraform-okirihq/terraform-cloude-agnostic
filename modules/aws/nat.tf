# Private subnets get a route table; with enable_nat_gateway they egress via a
# single NAT gateway (in the first public subnet) with a static Elastic IP.

locals {
  create_nat     = var.enable_nat_gateway && length(local.public_subnets) > 0 && length(local.private_subnets) > 0
  nat_subnet_key = try(sort(keys(local.public_subnets))[0], null)
}

resource "aws_eip" "nat" {
  count = local.create_nat ? 1 : 0

  region = var.region
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.create_nat ? 1 : 0

  region        = var.region
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.this[local.nat_subnet_key].id
  tags          = merge(local.tags, { Name = "${local.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count = length(local.private_subnets) > 0 ? 1 : 0

  region = var.region
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-private" })
}

resource "aws_route" "private_nat" {
  count = local.create_nat ? 1 : 0

  region                 = var.region
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  region         = var.region
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[0].id
}
