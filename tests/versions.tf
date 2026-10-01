# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The root the tests run from: `tofu -chdir=tests init`, then
# `tofu -chdir=tests test -test-directory=.`. It declares the providers the
# module under test needs, so init installs them and this directory can
# carry its own lock file; it creates nothing itself. Each *.tftest.hcl says
# what it holds and which providers it mocks. No test makes an AWS call.

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
