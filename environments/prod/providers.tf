# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# One Region serves the whole environment: the instance, its queues, flows,
# Lambdas and prompt all live in var.aws_region. flowascode takes
# hashicorp/aws's configuration vocabulary, so the same credentials serve
# both; awscc takes the same credentials and region.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      "hollow-hour-example-terraform" = "true"
      "environment"                   = var.environment
    }
  }
}

provider "flowascode" {
  region = var.aws_region
}

# awscc (the prompt, modules/hollow-hour/prompts.tf) has no default_tags, so
# the prompt carries the two tags itself, and none of aws's skip_ flags.
provider "awscc" {
  region = var.aws_region
}
