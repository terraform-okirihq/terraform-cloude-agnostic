# HCP Terraform / Terraform Enterprise workspaces.
#
# Create workspaces such as foundation-dev and foundation-prod tagged
# "foundation", then set the workspace variable `environment` (dev/prod) and
# your cloud credentials (ideally dynamic provider credentials / OIDC).
#
#   terraform login
#   terraform init
#   terraform workspace select foundation-dev
#   terraform plan
terraform {
  required_version = ">= 1.9.0"

  cloud {
    organization = "my-org"
    workspaces {
      tags = ["foundation"]
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9.0"
    }
  }
}

variable "project_id" {
  type = string
}

# HCP workspace names ("foundation-dev") are longer than the environment
# name, so pass it explicitly as a workspace variable.
variable "environment" {
  type = string
}

provider "google" {
  project = var.project_id
}

module "foundation" {
  source = "../../modules/gcp"

  name        = "acme"
  environment = var.environment
  region      = "europe-west1"
  project_id  = var.project_id
}
