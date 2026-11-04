# Only aws + random are mocked: proves modules/aws needs no other provider.
mock_provider "aws" {
  source = "./tests/mocks/aws"
}

mock_provider "random" {}

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
    condition     = output.subnet_cidrs == { public = "10.0.0.0/24", private = "10.0.10.0/24" }
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
      web = { subnet = "public", size = "medium", public_ip = true, user_data = "#cloud-config\n" }
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
