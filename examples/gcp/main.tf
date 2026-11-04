# Plain Terraform usage. Authenticate with
# `gcloud auth application-default login` (or workload identity in CI).
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

variable "project_id" {
  type = string
}

variable "environment" {
  type    = string
  default = null
}

provider "google" {
  project = var.project_id
}

module "foundation" {
  # Registry: source = "<namespace>/foundation/multicloud//modules/gcp"
  source = "../../modules/gcp"

  name         = "acme"
  environment  = var.environment
  region       = "europe-west1"
  project_id   = var.project_id
  network_cidr = "10.30.0.0/16"
  tags         = { owner = "platform-team" }
}

output "network_id" { value = module.foundation.network_id }
output "bucket" { value = module.foundation.storage_bucket_url }
