data "aws_availability_zones" "available" {
  count = var.availability_zones == null ? 1 : 0

  region = var.region
  state  = "available"
}

locals {
  azs         = var.availability_zones != null ? var.availability_zones : data.aws_availability_zones.available[0].names
  subnet_keys = sort(keys(local.subnets))
  subnet_az   = { for i, k in local.subnet_keys : k => local.azs[i % length(local.azs)] }

}

# --- Network ---------------------------------------------------------------

resource "aws_vpc" "this" {
  region               = var.region
  cidr_block           = var.network_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  region                  = var.region
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = local.subnet_az[each.key]
  map_public_ip_on_launch = each.value.public

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${each.key}"
    tier = each.value.public ? "public" : "private"
    # Lets EKS / AWS Load Balancer Controller find subnets for load balancers.
    (each.value.public ? "kubernetes.io/role/elb" : "kubernetes.io/role/internal-elb") = "1"
  })
}

resource "aws_internet_gateway" "this" {
  count = length(local.public_subnets) > 0 ? 1 : 0

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_route_table" "public" {
  count = length(local.public_subnets) > 0 ? 1 : 0

  region = var.region
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-public" })
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  region         = var.region
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public[0].id
}

# --- Storage ---------------------------------------------------------------

resource "random_id" "bucket" {
  count       = var.create_storage_bucket ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  count = var.create_storage_bucket ? 1 : 0

  region        = var.region
  bucket        = "${local.name_prefix}-${random_id.bucket[0].hex}"
  force_destroy = var.storage_force_destroy

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.create_storage_bucket ? 1 : 0

  region                  = var.region
  bucket                  = aws_s3_bucket.this[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  count = var.create_storage_bucket ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.create_storage_bucket ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.this[0].id

  rule {
    id     = "housekeeping"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = var.create_storage_bucket ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.this[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = local.kms_key_arn != null
  }
}
