locals {
  create_containers = length(local.containers) > 0
  public_containers = { for k, c in local.containers : k => c if c.public }

  # Tasks run in private subnets (egress via NAT); without private subnets they
  # run in public subnets with a public IP so they can still pull images.
  workload_subnet_ids      = length(local.private_subnet_keys) > 0 ? [for k in local.private_subnet_keys : aws_subnet.this[k].id] : [for s in aws_subnet.this : s.id]
  workload_needs_public_ip = length(local.private_subnet_keys) == 0
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
  count = length(local.public_containers) > 0 ? 1 : 0

  region            = var.region
  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from the internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
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

resource "aws_lb" "containers" {
  for_each = local.public_containers

  region                     = var.region
  name                       = substr("${local.name_prefix}-${each.key}", 0, 32)
  load_balancer_type         = "application"
  subnets                    = [for k in local.public_subnet_keys : aws_subnet.this[k].id]
  security_groups            = [aws_security_group.alb[0].id]
  drop_invalid_header_fields = true
  enable_deletion_protection = local.deletion_protection
  tags                       = local.tags

  lifecycle {
    precondition {
      condition     = length(distinct([for k in local.public_subnet_keys : local.subnet_az[k]])) >= 2
      error_message = "Public containers on AWS need public subnets in at least two availability zones."
    }
  }
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

resource "aws_lb_listener" "containers" {
  for_each = local.public_containers

  region            = var.region
  load_balancer_arn = aws_lb.containers[each.key].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.containers[each.key].arn
  }

  tags = local.tags
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

  depends_on = [aws_lb_listener.containers, aws_route.private_nat]
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
