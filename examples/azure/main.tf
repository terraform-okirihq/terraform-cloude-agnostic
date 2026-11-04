# Plain Terraform usage. Authenticate with `az login` (or ARM_* env vars in CI)
# and set ARM_SUBSCRIPTION_ID.
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# e.g. terraform apply -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
variable "ssh_public_key" {
  type = string
}

variable "environment" {
  type    = string
  default = null
}

module "foundation" {
  # Registry: source = "<namespace>/foundation/multicloud//modules/azure"
  source = "../../modules/azure"

  name         = "acme"
  environment  = var.environment
  region       = "westeurope"
  network_cidr = "10.20.0.0/16"
  tags         = { owner = "platform-team" }

  ssh_public_key = var.ssh_public_key
  ingress_rules = [
    { name = "ssh", from_port = 22, source_cidrs = ["203.0.113.0/24"] }, # your office/VPN range
  ]
  servers = {
    app = { size = "medium" }
  }
}

output "resource_group" { value = module.foundation.resource_group_name }
output "network_id" { value = module.foundation.network_id }
output "bucket" { value = module.foundation.storage_bucket_url }
output "servers" { value = module.foundation.servers }
