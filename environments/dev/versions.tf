# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Every root under environments/ is the same files; only terraform.tfvars
# differs (tests/environments.tftest.hcl holds that).
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
    flowascode = {
      source  = "flow-as-code/flowascode"
      version = "~> 0.1.2"
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
