# Alerts go to an SNS topic with an email subscription per address. Each
# recipient must confirm the subscription email AWS sends.

resource "aws_sns_topic" "alerts" {
  count = length(local.monitoring.alert_emails) > 0 ? 1 : 0

  region = var.region
  name   = "${local.name_prefix}-alerts"
  # The AWS-managed aws/sns key does not allow CloudWatch alarms to publish,
  # so the topic uses the customer-managed key (or SSE is off without one).
  kms_master_key_id = local.kms_key_arn
  tags              = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(local.monitoring.alert_emails)

  region    = var.region
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  alarm_actions = aws_sns_topic.alerts[*].arn
}

resource "aws_cloudwatch_metric_alarm" "server_cpu" {
  for_each = local.servers

  region              = var.region
  alarm_name          = "${local.name_prefix}-${each.key}-cpu-high"
  alarm_description   = "CPU above ${local.monitoring.cpu_alert_threshold}% on server ${each.key}"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.server[each.key].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.monitoring.cpu_alert_threshold
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "server_status" {
  for_each = local.servers

  region              = var.region
  alarm_name          = "${local.name_prefix}-${each.key}-status-check-failed"
  alarm_description   = "EC2 status check failing on server ${each.key}"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.server[each.key].id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  alarm_actions       = local.alarm_actions
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  for_each = local.databases

  region              = var.region
  alarm_name          = "${local.name_prefix}-${each.key}-db-cpu-high"
  alarm_description   = "CPU above ${local.monitoring.cpu_alert_threshold}% on database ${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this[each.key].identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.monitoring.cpu_alert_threshold
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  for_each = local.databases

  region              = var.region
  alarm_name          = "${local.name_prefix}-${each.key}-db-storage-low"
  alarm_description   = "Less than 10% free storage on database ${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this[each.key].identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = each.value.storage_gb * 1073741824 * 0.1
  alarm_actions       = local.alarm_actions
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "container_cpu" {
  for_each = local.containers

  region              = var.region
  alarm_name          = "${local.name_prefix}-${each.key}-container-cpu-high"
  alarm_description   = "CPU above ${local.monitoring.cpu_alert_threshold}% on container service ${each.key}"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = aws_ecs_cluster.this[0].name, ServiceName = aws_ecs_service.this[each.key].name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.monitoring.cpu_alert_threshold
  alarm_actions       = local.alarm_actions
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "function_errors" {
  for_each = local.functions

  region              = var.region
  alarm_name          = "${local.name_prefix}-${each.key}-function-errors"
  alarm_description   = "Errors in function ${each.key}"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.this[each.key].function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = local.tags
}
