# Root "switch" module: choose the cloud at plan time, e.g. in a CI matrix:
#   terraform apply -var cloud=azure -var region=westeurope
#
# Terraform configures every provider the root module declares, so all three
# provider blocks must be valid here, even for clouds you are not deploying to.
# Single-cloud users should prefer modules/<cloud> (see ../aws).
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.20"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

variable "cloud" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type    = string
  default = null
}

variable "gcp_project_id" {
  type    = string
  default = null
}

provider "aws" {
  region = var.cloud == "aws" ? var.region : "us-east-1"
}

provider "azurerm" {
  features {}
}

provider "google" {
  project = var.gcp_project_id
}

module "foundation" {
  # Registry: source = "<namespace>/foundation/multicloud"
  source = "../.."

  cloud       = var.cloud
  name        = "acme"
  environment = var.environment
  region      = var.region
  gcp         = { project_id = var.gcp_project_id }
}

output "foundation" {
  value = {
    cloud      = module.foundation.cloud
    network_id = module.foundation.network_id
    subnet_ids = module.foundation.subnet_ids
    bucket     = module.foundation.storage_bucket_url
  }
}
