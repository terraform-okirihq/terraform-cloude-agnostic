locals {
  k8s_enabled = local.kubernetes.enabled

  # Portable node sizes -> instance types. Any other value is passed through.
  node_instance_types = {
    small  = "t3.medium"
    medium = "m6i.large"
    large  = "m6i.xlarge"
  }

  k8s_node_subnet_ids = [for k in local.kubernetes.subnets : aws_subnet.this[k].id]
}

data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  count = local.k8s_enabled ? 1 : 0

  name               = "${local.name_prefix}-${var.region}-eks"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  count = local.k8s_enabled ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_nodes" {
  count = local.k8s_enabled ? 1 : 0

  name               = "${local.name_prefix}-${var.region}-eks-nodes"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "eks_nodes" {
  for_each = local.k8s_enabled ? toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ]) : toset([])

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# Created first so the retention period applies to control-plane logs.
resource "aws_cloudwatch_log_group" "eks" {
  count = local.k8s_enabled ? 1 : 0

  region            = var.region
  name              = "/aws/eks/${local.name_prefix}/cluster"
  retention_in_days = local.monitoring.log_retention_days
  tags              = local.tags
}

resource "aws_eks_cluster" "this" {
  count = local.k8s_enabled ? 1 : 0

  region                    = var.region
  name                      = local.name_prefix
  role_arn                  = aws_iam_role.eks_cluster[0].arn
  version                   = local.kubernetes.version
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  deletion_protection       = local.deletion_protection

  vpc_config {
    subnet_ids              = [for s in aws_subnet.this : s.id]
    endpoint_private_access = true
    endpoint_public_access  = local.kubernetes.public_endpoint
    public_access_cidrs     = local.kubernetes.public_endpoint ? local.kubernetes.authorized_cidrs : null
  }

  kubernetes_network_config {
    service_ipv4_cidr = local.kubernetes.service_cidr
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  dynamic "encryption_config" {
    for_each = local.kms_key_arn != null ? [1] : []
    content {
      resources = ["secrets"]
      provider {
        key_arn = local.kms_key_arn
      }
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(distinct([for k, s in local.subnets : local.subnet_az[k]])) >= 2
      error_message = "EKS needs subnets in at least two availability zones."
    }
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster, aws_cloudwatch_log_group.eks]
}

resource "aws_eks_node_group" "default" {
  count = local.k8s_enabled ? 1 : 0

  region          = var.region
  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = local.k8s_node_subnet_ids
  instance_types  = [lookup(local.node_instance_types, local.kubernetes.node_size, local.kubernetes.node_size)]
  disk_size       = local.kubernetes.node_disk_gb
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    min_size     = local.kubernetes.node_min
    max_size     = local.kubernetes.node_max
    desired_size = local.kubernetes.node_min
  }

  update_config {
    max_unavailable = 1
  }

  tags = local.tags

  lifecycle {
    # The cluster autoscaler owns the desired size after creation.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_nodes, aws_route.private_nat]
}
