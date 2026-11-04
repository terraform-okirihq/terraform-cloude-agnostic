terraform {
  required_version = ">= 1.9.0"

  # All providers are declared so the module can switch clouds, but only the
  # provider for the selected cloud is ever configured or called. Callers only
  # need a provider block for the cloud they actually deploy to.
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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}
