# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The module declares what it needs and configures nothing: each root under
# environments/ configures aws and flowascode for its Region.
#
# flowascode moves state across resource types, which needs Terraform 1.8 or
# OpenTofu 1.10; the roots' S3 backend lock object (use_lockfile) needs
# OpenTofu 1.10 or Terraform 1.11. CI tests OpenTofu only.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # 0.1.2 refuses at plan a Compare with no `next` action, which the
    # service refuses at create. A 0.x minor may change the schema, so the
    # constraint stays within 0.1.
    flowascode = {
      source  = "flow-as-code/flowascode"
      version = "~> 0.1.2"
    }
    # Zips lambdas/<name>/ at plan time: no build step, nothing committed.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    # Cloud Control, for the one resource hashicorp/aws has no type for: the
    # Connect prompt (prompts.tf). The package is hundreds of megabytes,
    # which is why CI caches the plugin directory (CONTRIBUTING.md).
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.104"
    }
    # The instance alias suffix: aliases are unique across every account.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
