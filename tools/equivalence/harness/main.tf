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
# passing each profile's values as -var flags, against a temporary copy of
# the module laid out as in the repository (check.mjs, `moduleCopy`), not
# the module itself, because of awscc (below). The defaults are prod's.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    flowascode = {
      source  = "flow-as-code/flowascode"
      version = "~> 0.1.2"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.104"
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

# awscc is declared because the module requires it, and configured by
# nothing here. It has no skip_credentials_validation or
# skip_requesting_account_id, and with a provider block carrying placeholder
# keys, region and skip_metadata_api_check it failed as it configured,
# before any resource was planned: "validating provider credentials:
# retrieving caller identity from STS: operation error STS:
# GetCallerIdentity ... api error InvalidClientTokenId" (risk E1,
# tasks/README.md; VERIFY.md, row T10, 2026-10-05). So in the copy
# check.mjs plans, the module's one awscc resource, the prompt
# (modules/hollow-hour/prompts.tf), is a terraform_data stand-in carrying
# the same attributes, every reference to it rewritten (check.mjs,
# `STAND_IN`): the copy holds no awscc resource, so awscc is never
# configured, and the prompt's binding is still compared by the name the
# module declares.

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
