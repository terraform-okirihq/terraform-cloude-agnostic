# Provider-free tests of the shared conventions in modules/context.

variables {
  name = "acme"
}

run "environment_defaults_to_workspace" {
  command = plan
  module {
    source = "./modules/context"
  }

  assert {
    condition     = output.environment == "default" && output.name_prefix == "acme-default"
    error_message = "Environment should fall back to terraform.workspace."
  }
}

run "explicit_environment_and_tags" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    environment = "staging"
    tags        = { owner = "platform" }
  }

  assert {
    condition = output.tags == {
      "managed-by"  = "terraform"
      "environment" = "staging"
      "workload"    = "acme"
      "owner"       = "platform"
    }
    error_message = "Tags not merged correctly."
  }
}

run "default_subnets_follow_network_cidr" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    network_cidr = "172.20.0.0/16"
  }

  assert {
    condition     = output.subnets["public-a"].cidr == "172.20.0.0/24" && output.subnets["public-b"].cidr == "172.20.1.0/24" && output.subnets["private-a"].cidr == "172.20.10.0/24" && output.subnets["private-b"].cidr == "172.20.11.0/24"
    error_message = "Default subnets not derived from network_cidr."
  }
}

run "rejects_bad_name" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}

run "rejects_bad_environment" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    environment = "PROD!"
  }

  expect_failures = [var.environment]
}

run "rejects_bad_cidr" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    network_cidr = "10.0.0.0/99"
  }

  expect_failures = [var.network_cidr]
}

run "rejects_bad_subnet_key" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    subnets = { "App_Tier" = { cidr = "10.0.1.0/24" } }
  }

  expect_failures = [var.subnets]
}

run "rejects_server_in_unknown_subnet" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    servers = { web = { subnet = "dmz" } }
  }

  expect_failures = [var.servers]
}

run "rejects_bad_ingress_rule" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    ingress_rules = [{ name = "ssh", from_port = 22, to_port = 21, source_cidrs = ["0.0.0.0/0"] }]
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_reserved_admin_username" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    admin_username = "admin"
  }

  expect_failures = [var.admin_username]
}

run "port_range_normalised" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    ingress_rules = [
      { name = "ssh", from_port = 22, source_cidrs = ["10.0.0.0/8"] },
      { name = "app", from_port = 8000, to_port = 8080, source_cidrs = ["10.0.0.0/8"] },
    ]
  }

  assert {
    condition     = output.ingress_rules[0].port_range == "22" && output.ingress_rules[1].port_range == "8000-8080"
    error_message = "port_range not normalised."
  }
}

run "servers_default_to_first_private_subnet" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    servers    = { api = {} }
    kubernetes = { enabled = true }
  }

  assert {
    condition     = output.servers["api"].subnet == "private-a" && tolist(output.kubernetes.subnets) == tolist(["private-a", "private-b"])
    error_message = "Workloads should default to private subnets."
  }
}

run "rejects_bad_database" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    databases = { app = { engine = "oracle" } }
  }

  expect_failures = [var.databases]
}

run "rejects_bad_function_runtime" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    functions = { api = { source_dir = ".", runtime = "ruby3.3" } }
  }

  expect_failures = [var.functions]
}

run "rejects_bad_kubernetes_scaling" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    kubernetes = { enabled = true, node_min = 5, node_max = 2 }
  }

  expect_failures = [var.kubernetes]
}

run "rejects_bad_retention" {
  command = plan
  module {
    source = "./modules/context"
  }

  variables {
    monitoring = { log_retention_days = 45 }
  }

  expect_failures = [var.monitoring]
}
