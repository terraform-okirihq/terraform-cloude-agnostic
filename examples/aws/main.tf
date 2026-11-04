# Plain Terraform usage: terraform init && terraform apply -var environment=dev
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = null # falls back to the workspace name
}

module "foundation" {
  # Registry: source = "<namespace>/foundation/multicloud//modules/aws"
  source = "../../modules/aws"

  name        = "acme"
  environment = var.environment
  region      = var.region
  tags        = { owner = "platform-team" }

  # Shell access via SSM Session Manager; no SSH key or open port 22 needed.
  ingress_rules = [
    { name = "https", from_port = 443, source_cidrs = ["0.0.0.0/0"] },
  ]

  servers = {
    web = {
      subnet    = "public-a"
      size      = "small"
      public_ip = true
      user_data = <<-EOT
        #cloud-config
        packages: [nginx]
      EOT
    }
    worker = { size = "medium", disk_size_gb = 50 } # private, egress via NAT
  }
}

output "network_id" { value = module.foundation.network_id }
output "subnet_ids" { value = module.foundation.subnet_ids }
output "bucket" { value = module.foundation.storage_bucket_url }
output "servers" { value = module.foundation.servers }
output "nat_public_ip" { value = module.foundation.nat_public_ip }
