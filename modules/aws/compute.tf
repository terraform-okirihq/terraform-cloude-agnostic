locals {
  # Portable size names -> AWS instance types. Any other value is passed through.
  instance_types = {
    small  = "t3.small"
    medium = "t3.large"
    large  = "m6i.xlarge"
  }

  create_servers = length(local.servers) > 0
  need_ami       = anytrue([for s in values(local.servers) : s.image == null])
}

data "aws_partition" "current" {}

# Latest Ubuntu 24.04 LTS from Canonical, used when a server sets no image.
data "aws_ami" "ubuntu" {
  count = local.need_ami ? 1 : 0

  region      = var.region
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_key_pair" "this" {
  count = local.create_servers && module.context.ssh_public_key != null ? 1 : 0

  region     = var.region
  key_name   = local.name_prefix
  public_key = module.context.ssh_public_key
  tags       = local.tags
}

# Instance role: SSM Session Manager gives shell access without opening port 22.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "servers" {
  count = local.create_servers ? 1 : 0

  name               = "${local.name_prefix}-${var.region}-servers"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = local.create_servers ? 1 : 0

  role       = aws_iam_role.servers[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "servers" {
  count = local.create_servers ? 1 : 0

  name = "${local.name_prefix}-${var.region}-servers"
  role = aws_iam_role.servers[0].name
  tags = local.tags
}

resource "aws_instance" "server" {
  for_each = local.servers

  region                      = var.region
  ami                         = coalesce(each.value.image, one(data.aws_ami.ubuntu[*].id))
  instance_type               = lookup(local.instance_types, each.value.size, each.value.size)
  subnet_id                   = aws_subnet.this[each.value.subnet].id
  vpc_security_group_ids      = [aws_security_group.servers.id]
  associate_public_ip_address = each.value.public_ip
  key_name                    = one(aws_key_pair.this[*].key_name)
  iam_instance_profile        = aws_iam_instance_profile.servers[0].name
  user_data                   = each.value.user_data
  user_data_replace_on_change = true
  monitoring                  = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.disk_size_gb
    encrypted             = true
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = "${local.name_prefix}-${each.key}" })
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}" })

  lifecycle {
    # A newer Ubuntu AMI must not silently replace running servers.
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy_attachment.ssm, aws_route.private_nat]
}
