# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# One Region serves the whole environment: the instance, its queues, flows
# and Lambdas all live in var.aws_region. flowascode takes hashicorp/aws's
# configuration vocabulary, so the same credentials serve both.

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
