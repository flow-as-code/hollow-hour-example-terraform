# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The whole environment: a Connect instance and everything in it. The module
# is the same for every environment; terraform.tfvars is the difference.

module "hollow_hour" {
  source = "../../modules/hollow-hour"

  environment = var.environment
  hours       = var.hours
  season      = var.season
}
