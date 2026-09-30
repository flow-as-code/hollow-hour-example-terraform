# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The root tools/equivalence/check.mjs plans, offline, to read the FlowDoc the
# flowascode provider computes for every flow and module in
# modules/hollow-hour. Never applied: the credentials below are placeholders
# that reach no account, and every skip_ flag keeps the providers from
# calling AWS while they configure. A plan of resources that do not exist
# yet makes no API call, and the module reads no data source that would.
#
# check.mjs plans it once per deploy profile (dev, qa, prod, prod-october),
# passing each profile's values as -var flags. The defaults are prod's.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    flowascode = {
      source  = "flow-as-code/flowascode"
      version = "~> 0.1.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "offline"
  secret_key                  = "offline"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

provider "flowascode" {
  region                      = "us-east-1"
  access_key                  = "offline"
  secret_key                  = "offline"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "hours" {
  type    = string
  default = "night_shift"
}

variable "season" {
  type    = string
  default = "standard"
}

module "hollow_hour" {
  source = "../../../modules/hollow-hour"

  environment = var.environment
  hours       = var.hours
  season      = var.season
}

output "flowdocs" {
  value = module.hollow_hour.flowdocs
}
