# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Every deploy profile side by side, for tests/environments.tftest.hcl: one
# module call per profile, each fed the values from its root's committed
# terraform.tfvars (read here with a regular expression, so the test follows
# the files rather than a copy of them). prod-october is prod's tfvars with
# the two October lines applied; prod-halloween-only changes the season
# alone.

locals {
  environments = ["dev", "qa", "prod"]

  tfvars = {
    for env in local.environments : env => {
      for m in regexall("(?m)^([a-z_]+)\\s*=\\s*\"([^\"]*)\"", file("${path.module}/../../../environments/${env}/terraform.tfvars")) :
      m[0] => m[1]
    }
  }

  profiles = {
    "dev"                 = local.tfvars["dev"]
    "qa"                  = local.tfvars["qa"]
    "prod"                = local.tfvars["prod"]
    "prod-october"        = merge(local.tfvars["prod"], { hours = "always_open", season = "halloween" })
    "prod-halloween-only" = merge(local.tfvars["prod"], { season = "halloween" })
  }
}

module "dev" {
  source      = "../../../modules/hollow-hour"
  environment = local.profiles["dev"].environment
  hours       = local.profiles["dev"].hours
  season      = local.profiles["dev"].season
}

module "qa" {
  source      = "../../../modules/hollow-hour"
  environment = local.profiles["qa"].environment
  hours       = local.profiles["qa"].hours
  season      = local.profiles["qa"].season
}

module "prod" {
  source      = "../../../modules/hollow-hour"
  environment = local.profiles["prod"].environment
  hours       = local.profiles["prod"].hours
  season      = local.profiles["prod"].season
}

module "prod_october" {
  source      = "../../../modules/hollow-hour"
  environment = local.profiles["prod-october"].environment
  hours       = local.profiles["prod-october"].hours
  season      = local.profiles["prod-october"].season
}

module "prod_halloween_only" {
  source      = "../../../modules/hollow-hour"
  environment = local.profiles["prod-halloween-only"].environment
  hours       = local.profiles["prod-halloween-only"].hours
  season      = local.profiles["prod-halloween-only"].season
}

output "tfvars" {
  value = local.tfvars
}

locals {
  modules = {
    "dev"                 = module.dev
    "qa"                  = module.qa
    "prod"                = module.prod
    "prod-october"        = module.prod_october
    "prod-halloween-only" = module.prod_halloween_only
  }
}

output "flowdocs" {
  value = { for name, m in local.modules : name => m.flowdocs }
}

output "flow_refs" {
  value = { for name, m in local.modules : name => m.flow_refs }
}

output "district_hours" {
  value = { for name, m in local.modules : name => m.district_hours }
}

output "season" {
  value = { for name, m in local.modules : name => m.season }
}

output "greeting_live_arns" {
  value = { for name, m in local.modules : name => m.greeting_live_arns }
}
