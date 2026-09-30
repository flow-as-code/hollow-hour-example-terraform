# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

provider "aws" {
  region = var.state_region

  default_tags {
    tags = {
      "hollow-hour-example-terraform" = "true"
      "environment"                   = "shared"
    }
  }
}
