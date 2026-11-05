locals {
  create_containers = length(local.containers) > 0
  public_containers = { for k, c in local.containers : k => c if c.public }

  # Tasks run in private subnets (egress via NAT); without private subnets they
  # run in public subnets with a public IP so they can still pull images.
  workload_subnet_ids      = length(local.private_subnet_keys) > 0 ? [for k in local.private_subnet_keys : aws_subnet.this[k].id] : [for s in aws_subnet.this : s.id]
  workload_needs_public_ip = length(local.private_subnet_keys) == 0

  alb_https  = var.certificate_arn != null
  create_alb = length(local.public_containers) > 0
}

resource "aws_ecs_cluster" "this" {
  count = local.create_containers ? 1 : 0

  region = var.region
  name   = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  count = local.create_containers ? 1 : 0

  name               = "${local.name_prefix}-${var.region}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count = local.create_containers ? 1 : 0

  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  count = local.create_containers ? 1 : 0

  name               = "${local.name_prefix}-${var.region}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.tags
}

resource "aws_cloudwatch_log_group" "containers" {
  for_each = local.containers

  region            = var.region
  name              = "/ecs/${local.name_prefix}/${each.key}"
  retention_in_days = local.monitoring.log_retention_days
  kms_key_id        = local.kms_key_arn
  tags              = local.tags
}

resource "aws_ecs_task_definition" "this" {
  for_each = local.containers

  region                   = var.region
  family                   = "${local.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu * 1024)
  memory                   = tostring(each.value.memory_gb * 1024)
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = each.key
    image        = each.value.image
    essential    = true
    portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]
    environment  = [for k, v in each.value.env : { name = k, value = v }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.containers[each.key].name
        awslogs-region        = var.region
        awslogs-stream-prefix = each.key
      }
    }
  }])

  tags = local.tags
}

# --- Public containers: one Application Load Balancer each ------------------

resource "aws_security_group" "alb" {
  count = length(local.public_containers) > 0 ? 1 : 0

  region      = var.region
  name        = "${local.name_prefix}-alb"
  description = "Public load balancers for container services"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:Public load balancer; with certificate_arn port 80 only redirects to HTTPS
  count = local.create_alb ? 1 : 0

  region            = var.region
  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from the internet (redirected to HTTPS when a certificate is set)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = local.create_alb && local.alb_https ? 1 : 0

  region            = var.region
  security_group_id = aws_security_group.alb[0].id
  description       = "HTTPS from the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  count = length(local.public_containers) > 0 ? 1 : 0

  region            = var.region
  security_group_id = aws_security_group.alb[0].id
  description       = "To targets inside the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.network_cidr
}

# --- Load balancer access logs (ALB only supports SSE-S3 for this bucket) ---

data "aws_elb_service_account" "this" {
  count  = local.create_alb ? 1 : 0
  region = var.region
}

resource "random_id" "alb_logs" {
  count       = local.create_alb ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket" "alb_logs" {
  count = local.create_alb ? 1 : 0

  region        = var.region
  bucket        = "${local.name_prefix}-alb-logs-${random_id.alb_logs[0].hex}"
  force_destroy = !local.deletion_protection
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count = local.create_alb ? 1 : 0

  region                  = var.region
  bucket                  = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  count = local.create_alb ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.alb_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  #checkov:skip=CKV_AWS_145:ALB access logs only support SSE-S3, not KMS
  count = local.create_alb ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.alb_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = local.create_alb ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = local.monitoring.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  count = local.create_alb ? 1 : 0

  statement {
    sid       = "ElbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this[0].arn]
    }
  }

  # Regions launched after August 2022 deliver logs with this service principal.
  statement {
    sid       = "ElbLogDeliveryService"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs[0].arn, "${aws_s3_bucket.alb_logs[0].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count = local.create_alb ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.alb_logs[0].id
  policy = data.aws_iam_policy_document.alb_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

resource "aws_lb" "containers" {
  #checkov:skip=CKV2_AWS_20:HTTP redirects to HTTPS when certificate_arn is set; without a certificate only HTTP is possible
  for_each = local.public_containers

  region                     = var.region
  name                       = substr("${local.name_prefix}-${each.key}", 0, 32)
  load_balancer_type         = "application"
  subnets                    = [for k in local.public_subnet_keys : aws_subnet.this[k].id]
  security_groups            = [aws_security_group.alb[0].id]
  drop_invalid_header_fields = true
  enable_deletion_protection = local.deletion_protection
  tags                       = local.tags

  access_logs {
    bucket  = aws_s3_bucket.alb_logs[0].id
    prefix  = each.key
    enabled = true
  }

  lifecycle {
    precondition {
      condition     = length(distinct([for k in local.public_subnet_keys : local.subnet_az[k]])) >= 2
      error_message = "Public containers on AWS need public subnets in at least two availability zones."
    }
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "containers" {
  for_each = local.public_containers

  region      = var.region
  name        = substr("${local.name_prefix}-${each.key}", 0, 32)
  port        = each.value.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = "/"
    matcher = "200-399"
  }

  tags = local.tags
}

# Port 80: redirect to HTTPS when a certificate is configured, else serve HTTP.
resource "aws_lb_listener" "containers" {
  #checkov:skip=CKV_AWS_2:Redirects to HTTPS when certificate_arn is set; HTTP only without a certificate
  #checkov:skip=CKV_AWS_103:TLS is configured on the HTTPS listener
  #checkov:skip=CKV_AWS_378:Redirects to HTTPS when certificate_arn is set; HTTP only without a certificate
  for_each = local.public_containers

  region            = var.region
  load_balancer_arn = aws_lb.containers[each.key].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.alb_https ? "redirect" : "forward"
    target_group_arn = local.alb_https ? null : aws_lb_target_group.containers[each.key].arn

    dynamic "redirect" {
      for_each = local.alb_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = local.tags
}

resource "aws_lb_listener" "containers_https" {
  for_each = local.alb_https ? local.public_containers : {}

  region            = var.region
  load_balancer_arn = aws_lb.containers[each.key].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.containers[each.key].arn
  }

  tags = local.tags
}

# --- AWS WAF in front of public load balancers -----------------------------

locals {
  waf_managed_rules = ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet", "AWSManagedRulesAmazonIpReputationList"]
  create_waf        = local.create_alb && var.enable_waf
}

resource "aws_wafv2_web_acl" "containers" {
  count = local.create_waf ? 1 : 0

  region = var.region
  name   = "${local.name_prefix}-containers"
  scope  = "REGIONAL"
  tags   = local.tags

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.waf_managed_rules
    content {
      name     = rule.value
      priority = rule.key + 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-containers"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "containers" {
  for_each = local.create_waf ? local.public_containers : {}

  region       = var.region
  resource_arn = aws_lb.containers[each.key].arn
  web_acl_arn  = aws_wafv2_web_acl.containers[0].arn
}

resource "aws_cloudwatch_log_group" "waf" {
  count = local.create_waf ? 1 : 0

  region            = var.region
  name              = "aws-waf-logs-${local.name_prefix}" # prefix required by WAF
  retention_in_days = local.monitoring.log_retention_days
  kms_key_id        = local.kms_key_arn
  tags              = local.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "containers" {
  count = local.create_waf ? 1 : 0

  region                  = var.region
  resource_arn            = aws_wafv2_web_acl.containers[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
}

resource "aws_ecs_service" "this" {
  for_each = local.containers

  region          = var.region
  name            = each.key
  cluster         = aws_ecs_cluster.this[0].id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.min_replicas
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.workload_subnet_ids
    security_groups  = [aws_security_group.workloads.id]
    assign_public_ip = local.workload_needs_public_ip
  }

  dynamic "load_balancer" {
    for_each = each.value.public ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.containers[each.key].arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.tags

  lifecycle {
    # Autoscaling owns the running count.
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.containers, aws_lb_listener.containers_https, aws_route.private_nat]
}

resource "aws_appautoscaling_target" "containers" {
  for_each = local.containers

  region             = var.region
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.this[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = each.value.min_replicas
  max_capacity       = each.value.max_replicas
}

resource "aws_appautoscaling_policy" "containers_cpu" {
  for_each = local.containers

  region             = var.region
  name               = "cpu-target-70"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.containers[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.containers[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.containers[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value = 70
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
