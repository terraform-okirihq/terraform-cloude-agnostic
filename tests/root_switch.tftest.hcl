# The root module needs all providers configured, so all are mocked here.
mock_provider "aws" {
  source = "./tests/mocks/aws"
}
mock_provider "azurerm" {
  source = "./tests/mocks/azurerm"
}
mock_provider "google" {
  source = "./tests/mocks/google"
}
mock_provider "random" {}

variables {
  name        = "acme"
  environment = "test"
}

run "aws" {
  variables {
    cloud   = "aws"
    region  = "us-east-1"
    servers = { app = {} }
  }

  assert {
    condition     = keys(output.servers) == ["app"] && output.nat_public_ip == "203.0.113.10"
    error_message = "Servers/NAT outputs not passed through."
  }

  assert {
    condition     = output.cloud == "aws" && output.name_prefix == "acme-test" && startswith(output.storage_bucket_url, "s3://")
    error_message = "AWS selection produced unexpected outputs."
  }

  assert {
    condition     = length(module.azure) == 0 && length(module.gcp) == 0 && output.azure_resource_group_name == null
    error_message = "Only the AWS module should be instantiated."
  }
}

run "azure" {
  variables {
    cloud  = "azure"
    region = "westeurope"
  }

  assert {
    condition     = output.network_name == "vnet-acme-test" && output.azure_resource_group_name == "rg-acme-test"
    error_message = "Azure selection produced unexpected outputs."
  }
}

run "gcp" {
  variables {
    cloud  = "gcp"
    region = "europe-west1"
    gcp    = { project_id = "acme-123" }
  }

  assert {
    condition     = output.network_name == "acme-test-vpc" && length(output.subnet_ids) == 2
    error_message = "GCP selection produced unexpected outputs."
  }
}

run "environment_defaults_to_workspace" {
  command = plan

  variables {
    cloud       = "aws"
    region      = "us-east-1"
    environment = null
  }

  # terraform test runs in the "default" workspace.
  assert {
    condition     = output.environment == "default" && output.name_prefix == "acme-default"
    error_message = "Environment should fall back to terraform.workspace."
  }
}

run "rejects_unknown_cloud" {
  command = plan

  variables {
    cloud  = "oracle"
    region = "x"
  }

  expect_failures = [var.cloud]
}

run "gcp_requires_project_id" {
  command = plan

  variables {
    cloud  = "gcp"
    region = "europe-west1"
  }

  expect_failures = [var.gcp]
}
