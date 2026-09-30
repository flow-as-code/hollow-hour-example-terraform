# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The bootstrap root: the one S3 bucket every environment keeps its state in,
# and nothing else. Each environment creates its own Connect instance, so
# there is nothing else to bootstrap. Applied once by an operator with their
# own credentials, never by deploy.yml; README.md, "Quickstart", has the
# order of commands.
#
# The S3 backend's lock object (use_lockfile, no DynamoDB table) needs
# OpenTofu 1.10, and Terraform 1.11 (where it left experiment; untested here).
# https://opentofu.org/docs/language/settings/backends/s3/

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
