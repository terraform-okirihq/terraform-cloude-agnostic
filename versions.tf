terraform {
  required_version = ">= 1.9.0"

  # All providers are declared so the module can switch clouds, but only the
  # provider for the selected cloud is ever configured or called. Callers only
  # need a provider block for the cloud they actually deploy to.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4, < 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11, < 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5, < 4.0"
    }
  }
}
