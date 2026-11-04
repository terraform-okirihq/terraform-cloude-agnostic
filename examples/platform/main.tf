# Full platform on one cloud: network, Kubernetes, databases, containers,
# serverless functions, encryption and alerting.
#
# Switch clouds by changing the module source and provider (and adding
# project_id on GCP); every input below works unchanged on all three.
#
#   terraform init
#   terraform apply -var 'alert_email=ops@example.com'
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
  default = "eu-west-1"
}

variable "alert_email" {
  type = string
}

module "platform" {
  # Registry: source = "<namespace>/foundation/multicloud//modules/aws"
  source = "../../modules/aws"

  name        = "acme"
  environment = "prod"
  region      = var.region

  kubernetes = {
    enabled          = true
    node_size        = "medium"
    node_min         = 2
    node_max         = 6
    authorized_cidrs = ["203.0.113.0/24"] # your office / VPN
  }

  databases = {
    app = { engine = "postgres", size = "medium", high_availability = true, backup_retention_days = 14 }
  }

  containers = {
    web = {
      image        = "public.ecr.aws/nginx/nginx:1.27"
      size         = "small"
      min_replicas = 2
      max_replicas = 10
    }
  }

  functions = {
    hello = { source_dir = "${path.module}/functions/hello", public = true }
  }

  security   = { customer_managed_keys = true, flow_logs = true }
  monitoring = { alert_emails = [var.alert_email], log_retention_days = 90 }

  deletion_protection = true
}

output "kubernetes" { value = module.platform.kubernetes }
output "databases" { value = module.platform.databases }
output "containers" { value = module.platform.containers }
output "functions" { value = module.platform.functions }
