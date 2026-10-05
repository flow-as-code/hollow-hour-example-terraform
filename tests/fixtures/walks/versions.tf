# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    flowascode = {
      source = "flow-as-code/flowascode"
    }
  }
}
