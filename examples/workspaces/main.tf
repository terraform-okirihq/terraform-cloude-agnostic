# Terraform CLI workspaces: one configuration, one state per environment.
#
#   terraform init
#   terraform workspace new dev    # or: terraform workspace select dev
#   terraform apply -var-file=env/dev.tfvars
#
# The module derives `environment` from terraform.workspace automatically,
# so resources are named acme-dev-*, acme-prod-*, ...
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # Workspaces work with any backend that supports them (s3, azurerm, gcs, ...):
  # backend "s3" {
  #   bucket               = "my-tf-state"
  #   key                  = "foundation/terraform.tfstate"
  #   region               = "us-east-1"
  #   workspace_key_prefix = "env"
  #   use_lockfile         = true
  # }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type = string
}

variable "network_cidr" {
  type = string
}

locals {
  # Guard against applying to the "default" workspace by accident.
  allowed_workspaces = ["dev", "staging", "prod"]
}

resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = contains(local.allowed_workspaces, terraform.workspace)
      error_message = "Select a workspace first: terraform workspace select <${join("|", local.allowed_workspaces)}>"
    }
  }
}

module "foundation" {
  source = "../../modules/aws"

  name         = "acme"
  region       = var.region
  network_cidr = var.network_cidr
  # environment omitted on purpose -> taken from terraform.workspace

  storage_force_destroy = terraform.workspace != "prod"
}

output "name_prefix" { value = module.foundation.name_prefix }
