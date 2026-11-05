# Only aws + random are mocked: proves modules/aws needs no other provider.
mock_provider "aws" {
  source = "./tests/mocks/aws"
}

mock_provider "random" {
  source = "./tests/mocks/random"
}

mock_provider "archive" {
  source = "./tests/mocks/archive"
}

variables {
  # Throwaway test-only public key; its private key was never kept.
  test_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDeNqobvAuJ4UXMGksAhTzBZv2zV3D19S3BPYhne8MQ6McHIBkGXprUeh2r7IjOmqAENp10hGuqe6pjKiRxngBHcBOfQQ452BCCVhQd/BfWrsOEmP7qjntmRyX5biRBVrY1nLz9IN800k7uUlhLpOScNLuOeKudIXFsxYYocmE9ECmt3HbQcokJp3TDUoFIaF5mLcwK4rzyw37eC1MyFgwhQGEgFzkdVdLABcxDf7MdP3pdfXfKnO8Izl2kc91EHlI+x206r0/vI0q7mC89E+cXYGhRuab02odNvWq66gW6HpT3dUPpwA4EUrDOeS/dJfP4KjtVRn7B03d7B7u7aPnp test-only@example"
  name                = "acme"
  environment         = "test"
  region              = "us-east-1"
}

run "network_and_storage_defaults" {
  module {
    source = "./modules/aws"
  }

  assert {
    condition     = output.name_prefix == "acme-test"
    error_message = "Unexpected name prefix."
  }

  assert {
    condition     = output.subnet_cidrs == { public-a = "10.0.0.0/24", public-b = "10.0.1.0/24", private-a = "10.0.10.0/24", private-b = "10.0.11.0/24" }
    error_message = "Default subnets were not derived from network_cidr."
  }

  assert {
    condition     = startswith(output.storage_bucket_name, "acme-test-") && startswith(output.storage_bucket_url, "s3://")
    error_message = "Bucket name/URL is wrong."
  }

  assert {
    condition     = output.nat_public_ip == "203.0.113.10" && length(aws_nat_gateway.this) == 1
    error_message = "NAT gateway should be created by default."
  }

  assert {
    condition     = output.servers == {} && length(aws_iam_role.servers) == 0
    error_message = "No server resources should exist without servers."
  }
}

run "servers_and_firewall" {
  module {
    source = "./modules/aws"
  }

  variables {
    ssh_public_key = var.test_ssh_public_key
    ingress_rules = [
      { name = "https", from_port = 443, source_cidrs = ["0.0.0.0/0"] },
      { name = "app", from_port = 8000, to_port = 8080, source_cidrs = ["10.1.0.0/16", "10.2.0.0/16"] },
    ]
    servers = {
      web = { subnet = "public-a", size = "medium", public_ip = true, user_data = "#cloud-config\n" }
      api = {}
    }
  }

  assert {
    condition     = aws_instance.server["web"].instance_type == "t3.large" && aws_instance.server["api"].instance_type == "t3.small"
    error_message = "Portable sizes not mapped to AWS instance types."
  }

  assert {
    condition     = aws_instance.server["web"].metadata_options[0].http_tokens == "required" && aws_instance.server["web"].root_block_device[0].encrypted
    error_message = "Servers must enforce IMDSv2 and encrypted root volumes."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.custom) == 3
    error_message = "Expected one SG rule per (rule, CIDR) pair."
  }

  assert {
    condition     = output.servers["web"].public_ip == "203.0.113.20" && output.servers["api"].public_ip == null
    error_message = "Only servers with public_ip = true should expose a public IP."
  }

  assert {
    condition     = length(aws_key_pair.this) == 1 && length(aws_iam_instance_profile.servers) == 1
    error_message = "Key pair and SSM instance profile should be created."
  }
}

run "no_nat_no_bucket" {
  module {
    source = "./modules/aws"
  }

  variables {
    enable_nat_gateway    = false
    create_storage_bucket = false
    availability_zones    = ["us-east-1a"]
  }

  assert {
    condition     = output.nat_public_ip == null && output.storage_bucket_name == null
    error_message = "NAT and bucket should be disabled."
  }
}

run "platform_services" {
  module {
    source = "./modules/aws"
  }

  variables {
    kubernetes = { enabled = true, node_size = "large", node_min = 2, node_max = 6, authorized_cidrs = ["203.0.113.0/24"] }
    databases = {
      app       = { engine = "postgres", size = "medium", high_availability = true }
      analytics = { engine = "mysql", storage_gb = 100 }
    }
    containers = {
      web    = { image = "nginx:1.27", size = "medium", max_replicas = 5 }
      worker = { image = "busybox:1.36", public = false }
    }
    functions = {
      api = { source_dir = "./examples/platform/functions/hello", public = true }
      job = { source_dir = "./examples/platform/functions/hello", runtime = "nodejs22" }
    }
    security   = { customer_managed_keys = true }
    monitoring = { alert_emails = ["ops@example.com"] }
  }

  # Kubernetes
  assert {
    condition     = aws_eks_cluster.this[0].access_config[0].authentication_mode == "API" && length(aws_eks_cluster.this[0].encryption_config) == 1
    error_message = "EKS must use API auth and envelope-encrypt secrets with the CMK."
  }
  assert {
    condition     = tolist(aws_eks_node_group.default[0].instance_types) == tolist(["m6i.xlarge"]) && aws_eks_node_group.default[0].scaling_config[0].max_size == 6
    error_message = "Node size/scaling not mapped."
  }
  assert {
    condition     = length(aws_eks_node_group.default[0].subnet_ids) == 2
    error_message = "Nodes should default to both private subnets."
  }
  assert {
    condition     = startswith(output.kubernetes.kubeconfig_command, "aws eks update-kubeconfig")
    error_message = "kubeconfig command missing."
  }

  # Databases
  assert {
    condition     = aws_db_instance.this["app"].multi_az && aws_db_instance.this["app"].instance_class == "db.m7g.large" && aws_db_instance.this["app"].engine_version == "16"
    error_message = "Postgres HA/size/version not mapped."
  }
  assert {
    condition     = aws_db_instance.this["analytics"].engine == "mysql" && aws_db_instance.this["analytics"].engine_version == "8.0" && !aws_db_instance.this["analytics"].publicly_accessible
    error_message = "MySQL settings wrong or database exposed."
  }
  assert {
    condition     = aws_db_instance.this["app"].storage_encrypted && aws_db_instance.this["app"].manage_master_user_password && aws_db_instance.this["app"].deletion_protection
    error_message = "Databases must be encrypted, use managed passwords and be deletion protected."
  }
  assert {
    condition     = output.databases["app"].port == 5432 && output.databases["analytics"].port == 3306 && startswith(output.databases["app"].credentials_secret, "arn:aws:secretsmanager")
    error_message = "Database outputs wrong."
  }

  # Containers
  assert {
    condition     = aws_ecs_task_definition.this["web"].cpu == "1024" && aws_ecs_task_definition.this["web"].memory == "2048"
    error_message = "Container size not mapped to Fargate cpu/memory."
  }
  assert {
    condition     = length(aws_lb.containers) == 1 && output.containers["web"].url == "http://mock-123.us-east-1.elb.amazonaws.com" && output.containers["worker"].url == null
    error_message = "Only public containers get a load balancer URL."
  }
  assert {
    condition     = aws_appautoscaling_target.containers["web"].max_capacity == 5
    error_message = "Autoscaling max not applied."
  }

  # Functions
  assert {
    condition     = aws_lambda_function.this["api"].handler == "main.handler" && aws_lambda_function.this["job"].handler == "index.handler" && aws_lambda_function.this["job"].runtime == "nodejs22.x"
    error_message = "Runtime/handler convention not applied."
  }
  assert {
    condition     = aws_lambda_function_url.this["api"].authorization_type == "NONE" && aws_lambda_function_url.this["job"].authorization_type == "AWS_IAM" && length(aws_lambda_permission.public_invoke) == 1
    error_message = "Only public functions may have unauthenticated URLs."
  }

  # Security + monitoring
  assert {
    condition     = output.kms_key_id != null && aws_kms_key.this[0].enable_key_rotation && length(aws_flow_log.this) == 1
    error_message = "CMK with rotation and VPC flow logs expected."
  }
  assert {
    condition     = aws_sns_topic.alerts[0].kms_master_key_id == output.kms_key_id && aws_cloudwatch_log_group.containers["web"].kms_key_id == output.kms_key_id
    error_message = "Alert topic and log groups must use the CMK (aws/sns blocks CloudWatch alarms)."
  }
  assert {
    condition     = length(aws_wafv2_web_acl_association.containers) == 1 && length(aws_wafv2_web_acl.containers[0].rule) == 3 && contains([for r in aws_wafv2_web_acl.containers[0].rule : r.name], "AWSManagedRulesKnownBadInputsRuleSet")
    error_message = "Public load balancers must be protected by WAF managed rules."
  }
  assert {
    condition     = aws_lb.containers["web"].access_logs[0].enabled && aws_db_instance.this["app"].performance_insights_enabled && aws_db_instance.this["app"].monitoring_interval == 60
    error_message = "ALB access logs and RDS monitoring expected."
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1 && length(aws_cloudwatch_metric_alarm.database_cpu) == 2 && length(aws_cloudwatch_metric_alarm.function_errors) == 2
    error_message = "Alerts not wired."
  }
}

run "eks_needs_two_azs" {
  command = plan
  module {
    source = "./modules/aws"
  }

  variables {
    availability_zones = ["us-east-1a"]
    kubernetes         = { enabled = true }
  }

  expect_failures = [aws_eks_cluster.this]
}

run "https_load_balancer" {
  module {
    source = "./modules/aws"
  }

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    containers      = { web = { image = "nginx:1.27" } }
  }

  assert {
    condition     = aws_lb_listener.containers["web"].default_action[0].type == "redirect" && aws_lb_listener.containers["web"].default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "Port 80 must redirect to HTTPS when a certificate is set."
  }
  assert {
    condition     = aws_lb_listener.containers_https["web"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS listener must enforce TLS 1.2+."
  }
  assert {
    condition     = startswith(output.containers["web"].url, "https://")
    error_message = "Container URL should be HTTPS."
  }
}

run "no_cmk_means_no_sns_encryption" {
  module {
    source = "./modules/aws"
  }

  variables {
    security   = { customer_managed_keys = false }
    monitoring = { alert_emails = ["ops@example.com"] }
  }

  assert {
    condition     = output.kms_key_id == null && aws_sns_topic.alerts[0].kms_master_key_id == null
    error_message = "Without a CMK the topic must not use aws/sns, which CloudWatch alarms cannot publish to."
  }
}
