# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The four things an environment chooses, set in terraform.tfvars. Nothing
# here is a secret, and no instance id or account id is ever an input: the
# environment creates its own instance.

variable "environment" {
  description = "The environment's name: dev, qa or prod."
  type        = string
}

variable "aws_region" {
  description = "The Region the environment's instance and everything in it lives in."
  type        = string
}

variable "hours" {
  description = "The hours profile the district crews keep: always_open or night_shift."
  type        = string
}

variable "season" {
  description = "The greeting the hotline invokes: standard or halloween."
  type        = string
}
