# Code layout convention (same on every cloud):
#   python: <source_dir>/main.py  defining  def <entry_point>(event, context)
#   node:   <source_dir>/index.js exporting <entry_point>
locals {
  lambda_runtimes = {
    "python3.11" = "python3.11"
    "python3.12" = "python3.12"
    "nodejs20"   = "nodejs20.x"
    "nodejs22"   = "nodejs22.x"
  }
  create_functions = length(local.functions) > 0
}

data "archive_file" "functions" {
  for_each = local.functions

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.root}/.terraform/functions/${local.name_prefix}-${each.key}.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "functions" {
  count = local.create_functions ? 1 : 0

  name               = "${local.name_prefix}-${var.region}-functions"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "functions" {
  for_each = local.create_functions ? toset([
    "service-role/AWSLambdaVPCAccessExecutionRole",
    "AWSXRayDaemonWriteAccess",
  ]) : toset([])

  role       = aws_iam_role.functions[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

resource "aws_cloudwatch_log_group" "functions" {
  for_each = local.functions

  region            = var.region
  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = local.monitoring.log_retention_days
  kms_key_id        = local.kms_key_arn
  tags              = local.tags
}

resource "aws_lambda_function" "this" {
  for_each = local.functions

  region           = var.region
  function_name    = "${local.name_prefix}-${each.key}"
  role             = aws_iam_role.functions[0].arn
  runtime          = local.lambda_runtimes[each.value.runtime]
  handler          = "${each.value.language == "python" ? "main" : "index"}.${each.value.entry_point}"
  filename         = data.archive_file.functions[each.key].output_path
  source_code_hash = data.archive_file.functions[each.key].output_base64sha256
  memory_size      = each.value.memory_mb
  timeout          = each.value.timeout_seconds
  kms_key_arn      = local.kms_key_arn

  dynamic "environment" {
    for_each = length(each.value.env) > 0 ? [1] : []
    content {
      variables = each.value.env
    }
  }

  # Run inside the VPC so functions can reach databases; egress via NAT.
  vpc_config {
    subnet_ids         = local.workload_subnet_ids
    security_group_ids = [aws_security_group.workloads.id]
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy_attachment.functions, aws_cloudwatch_log_group.functions]
}

resource "aws_lambda_function_url" "this" {
  for_each = local.functions

  region             = var.region
  function_name      = aws_lambda_function.this[each.key].function_name
  authorization_type = each.value.public ? "NONE" : "AWS_IAM"
}

# Public URLs need both permissions since AWS's October 2025 change.
resource "aws_lambda_permission" "public_url" {
  #checkov:skip=CKV_AWS_301:Only created for functions with public = true
  for_each = { for k, f in local.functions : k => f if f.public }

  region                 = var.region
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this[each.key].function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "public_invoke" {
  #checkov:skip=CKV_AWS_301:Only created for functions with public = true; limited to calls via the function URL
  for_each = { for k, f in local.functions : k => f if f.public }

  region                   = var.region
  statement_id             = "AllowPublicInvokeViaUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.this[each.key].function_name
  principal                = "*"
  invoked_via_function_url = true
}
