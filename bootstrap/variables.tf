# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

variable "state_region" {
  description = "The Region of the state bucket, and so the backend region of every environment root, whatever Region that environment's instance is in."
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "The state bucket's name before its random suffix. Bucket names are global, so the suffix keeps two copies of this repository apart."
  type        = string
  default     = "hollow-hour-example-terraform-tfstate"
}
